#!/bin/bash
DEFAULT_CERT_DIR=".cert"
DEFAULT_SSL_CONF="openssl.cnf"

check_env() {
    openssl version 2> /dev/null 1> /dev/null
    if [ $? -ne 0 ]; then
        echo "找不到openssl命令，请先安装openssl！"
        exit 1
    fi
    
    cut --version 2> /dev/null 1> /dev/null
    if [ $? -ne 0 ]; then
        echo "找不到cut命令，请先安装cut！"
        exit 1
    fi
    
    realpath --version 2> /dev/null 1> /dev/null
    if [ $? -ne 0 ]; then
        echo "找不到realpath命令，请先安装realpath！"
        exit 1
    fi
    
    cp --version 2> /dev/null 1> /dev/null
    if [ $? -ne 0 ]; then
        echo "找不到cp命令，请先安装cp！"
        exit 1
    fi
    
    ssl_conf="`pwd`/$DEFAULT_SSL_CONF"
    if [ ! -f "$ssl_conf" ]; then
        echo "找不到openssl配置文件，请将其放置于当前目录下并命名为\"$DEFAULT_SSL_CONF\"！"
        exit 1
    fi
}
try_mkdir() {
    if [ -d $1 ];then
        return 1
    fi
    mkdir $1
    if [ $? -ne 0 ]; then
        target="`pwd`/$1"
        echo "创建 $target 失败！请手动检查目录"
        exit 1
    fi
    return 0
}
mk_ca_env() {
    touch index.txt
    echo -n "00" > serial
    echo -n "00" > crlnumber
    mkdir newcerts
    mkdir requests
    gen_crl
}
output_cert() {
    openssl x509 -in certificate.crt -text -noout
}
output_request() {
    openssl req -in request.csr -text -noout
}
gen_crl() {
    openssl ca -config "$ssl_conf" -gencrl -out current.crl 2> /dev/null 1> /dev/null
}
mk_chain_crt() {
    cat certificate.crt > chain.crt
    if [ "`pwd`" != "$root_dir/$DEFAULT_CERT_DIR" ]; then
        cat ../../$DEFAULT_CERT_DIR/chain.crt >> chain.crt
    fi
}
mk_chain_crl() {
    rm -f chain.crl
    if [ -f current.crl ];then
        cat current.crl > chain.crl
    else
        touch chain.crl
    fi
    if [ "`pwd`" != "$root_dir/$DEFAULT_CERT_DIR" ]; then
        cat ../../$DEFAULT_CERT_DIR/chain.crl >> chain.crl
    fi
}
update_sub_chain_crl() {
    for path in `ls`
    do
        if [ -d $path/$DEFAULT_CERT_DIR ]; then
            cd $path/$DEFAULT_CERT_DIR
            mk_chain_crl
            cd ..
            update_sub_chain_crl
            cd ..
        fi
    done
}
vertify_cert() {
    openssl verify -no-CAfile -no-CApath -no-CAstore -crl_check_all -verbose -show_chain -CAfile "$root_dir/$DEFAULT_CERT_DIR/certificate.crt" -untrusted chain.crt -CRLfile chain.crl certificate.crt
    return $?
}
sign_cert() {
    days="$1"
    serial="`cat ../../$DEFAULT_CERT_DIR/serial`"
    cp request.csr ../../$DEFAULT_CERT_DIR/requests/$serial.csr
    path="`pwd`"
    cd ../../$DEFAULT_CERT_DIR
    echo "接下来Openssl将会展示你的证书请求信息，请检查并确认是否正确"
    openssl ca -config "$ssl_conf" -days "$days" -in requests/$serial.csr
    if [ $? -ne 0 ]; then
        echo "生成失败！"
        cd ..
        rm -rf "$DEFAULT_CERT_DIR"
        exit 1
    fi
    cd "$path"
    cp ../../$DEFAULT_CERT_DIR/newcerts/$serial.pem certificate.crt
}
input_san() {
    san=""
    while :
    do
        echo "当前SAN内容: $san"
        echo "请添加SAN:"
        echo "1. 域名"
        echo "2. IP"
        echo "3. 完成"
        read opt
        case $opt in
            1)
                echo "请输入域名："
                read domain
                if [ -z $san ]; then
                    san="DNS:$domain"
                else
                    san="$san,DNS:$domain"
                fi
            ;;
            2)
                echo "请输入IP："
                read ip
                if [ -z $san ]; then
                    san="IP:$ip"
                else
                    san="$san,IP:$ip"
                fi
            ;;
            3)
                if [ -z $san ]; then
                    echo "SAN不允许为空"
                else
                    echo "当前SAN内容为：$san"
                    echo "请确认是否正确（Y）："
                    read opt
                    if [ "$opt" = "Y" ]; then
                        break
                    fi
                fi
            ;;
            *)
                echo "无效的选项！"
            ;;
        esac
    done
}


echo "欢迎使用个人证书链管理脚本！"
echo "开发者: starua<starua@starua.me>"
check_env
if [ ! $1 ]; then
    echo "请在第一个参数处指定目标根目录"
    exit 1
fi
root_dir="$1"
if [ -d "$root_dir" ]; then
    cd "$root_dir"
    root_dir="`pwd`"
    while :
    do
        path="`pwd`"
        path="`realpath "$path" --relative-to="$root_dir"`"
        if [ $path = "." ]; then
            path=""
        fi
        if [ ! -d $DEFAULT_CERT_DIR ]; then
            echo "当前路径 <root>/$path 不存在证书"
            echo "输入Y以创建证书，输入其他回退到父目录："
            read opt
            if [ "$opt" != "Y" ]; then
                if [ "`pwd`" = $root_dir ]; then
                    echo "退出"
                    exit 0
                else
                    cd ..
                fi
            else
                break
            fi
        fi
        echo "当前目录 <root>/$path"
        echo "输入\".\"编辑当前证书，输入目录名以进入目录"
        read long_dir
        if [ "$long_dir" = "." ]; then
            break
        else
            index=1
            if [ -z "`echo "$long_dir" | grep "/"`" ]; then
                single=1
            else
                single=0
            fi
            while :
            do
                dir=`echo "$long_dir" | cut -d "/" -f "$index"`
                if [ -z "$dir" ]; then
                    break
                fi
                if [ -z "`echo "$dir" | cut -d "." -f 1`" ]; then
                    echo "不允许创建隐藏目录"
                    exit 1
                fi
                try_mkdir "$dir"
                if [ $? -eq 0 ]; then
                    cd "$dir"
                    break
                else
                    cd "$dir"
                    if [ ! -d $DEFAULT_CERT_DIR ]; then
                        break
                    fi
                fi
                index=`expr $index + 1`
                if [ $single -eq 1 ]; then
                    break
                fi
            done
        fi
    done
else
    mkdir -p "$root_dir"
    if [ $? -ne 0 ]; then
        echo "创建 $root_dir 失败！请手动检查目录"
        exit 1
    else
        cd "$root_dir"
        root_dir="`pwd`"
    fi
fi

if [ "`pwd`" = $root_dir ]; then
    is_root=1
else
    is_root=0
fi

try_mkdir "$DEFAULT_CERT_DIR"
if [ $? -ne 0 ]; then
    echo "请选择你要执行的操作："
    echo "1. 查看证书信息"
    echo "2. 复制证书和其他文件到其他位置"
    echo "3. 吊销证书"
    echo "4. 验证证书有效性"
    read opt
    case $opt in
        1)
            cd $DEFAULT_CERT_DIR
            if [ ! -f "certificate.crt" ]; then
                echo "找不到证书！"
                exit 1
            fi
            output_cert
        ;;
        2)
            if [ ! -f "certificate.crt" ]; then
                echo "找不到证书！"
                exit 1
            fi
            echo "请输入目标路径："
            read path
            cp "$DEFAULT_CERT_DIR/certificate.crt" "$path"
            cp "$DEFAULT_CERT_DIR/private.key" "$path"
            cp "$DEFAULT_CERT_DIR/chain.crt" "$path"
            if [ -f "$DEFAULT_CERT_DIR/current.crl" ]; then
                cp "$DEFAULT_CERT_DIR/current.crl" "$path"
            fi
        ;;
        3)
            if [ $is_root -eq 1 ]; then
                echo "无法吊销根证书！"
                exit 1
            fi
            cert="`pwd`/$DEFAULT_CERT_DIR/certificate.crt"
            cd ../$DEFAULT_CERT_DIR
            openssl ca -config "$ssl_conf" -revoke "$cert"
            gen_crl
            mk_chain_crl
            cd ..
            update_sub_chain_crl
        ;;
        4)
            cd $DEFAULT_CERT_DIR
            vertify_cert
            if [ $? -eq 0 ]; then
                echo "证书有效！"
            else
                echo "证书无效！"
            fi
        ;;
        *)
            echo "输入错误！"
            exit 1
        ;;
    esac
else
    cd "$DEFAULT_CERT_DIR"
    if [ $is_root -eq 1 ]; then
        echo "---------生成根证书---------"
        echo "请指定根证书有效期（天）："
        read days
        echo "接下来请在openssl命令行中输入你的信息"
        openssl req -config "$ssl_conf" -new -x509 -days "$days" -out certificate.crt
        if [ $? -ne 0 ]; then
            echo "生成失败！"
            cd ..
            rm -rf "$DEFAULT_CERT_DIR"
            exit 1
        fi
        mk_ca_env
        mk_chain_crt
        mk_chain_crl
        vertify_cert
        if [ $? -ne 0 ]; then
            echo "生成的证书无效！"
            exit 1
        fi
        echo "生成完成！请检查证书信息："
        output_cert
    else
        echo "请选择你要生成的证书类型："
        echo "1. 中间CA证书"
        echo "2. 网站证书"
        echo "3. VPN服务器证书"
        echo "4. VPN客户端证书"
        read opt
        case $opt in
            1)
                echo "---------生成中间CA证书---------"
                echo "请指定证书有效期（天）："
                read days
                echo "请指定证书路径长度："
                read pathlen
                # 谢谢你啊OpenSSL，加了-addext就忽略-reqexts真是聪明的设计呢，呵呵
                openssl req -config "$ssl_conf" -new -out request.csr\
                -addext "basicConstraints = critical, CA:true, pathlen:$pathlen"\
                -addext "keyUsage = critical, cRLSign, digitalSignature, keyCertSign"\
                -addext "subjectKeyIdentifier = hash"
                if [ $? -ne 0 ]; then
                    echo "生成失败！"
                    cd ..
                    rm -rf "$DEFAULT_CERT_DIR"
                    exit 1
                fi
                sign_cert "$days"
                mk_ca_env
                mk_chain_crt
                mk_chain_crl
                vertify_cert
                if [ $? -ne 0 ]; then
                    echo "生成的证书无效！"
                    exit 1
                fi
                echo "生成完成！请检查证书信息："
                output_cert
            ;;
            2)
                echo "---------生成https证书---------"
                echo "请指定证书有效期（天）："
                read days
                input_san
                # 谢谢你啊OpenSSL，加了-addext就忽略-reqexts真是聪明的设计呢，呵呵
                openssl req -config "$ssl_conf" -new -out request.csr\
                -addext "basicConstraints = critical, CA:FALSE"\
                -addext "keyUsage = critical, digitalSignature, keyEncipherment"\
                -addext "extendedKeyUsage = critical, serverAuth"\
                -addext "subjectKeyIdentifier = hash"\
                -addext "subjectAltName = $san"
                if [ $? -ne 0 ]; then
                    echo "生成失败！"
                    cd ..
                    rm -rf "$DEFAULT_CERT_DIR"
                    exit 1
                fi
                sign_cert "$days"
                mk_chain_crt
                mk_chain_crl
                vertify_cert
                if [ $? -ne 0 ]; then
                    echo "生成的证书无效！"
                    exit 1
                fi
                echo "生成完成！请检查证书信息："
                output_cert
            ;;
            3)
                echo "---------生成VPN服务器证书---------"
                echo "请指定证书有效期（天）："
                read days
                input_san
                openssl req -config "$ssl_conf" -new -out request.csr\
                -addext "basicConstraints = critical, CA:FALSE"\
                -addext "keyUsage = critical, digitalSignature, keyEncipherment, keyAgreement"\
                -addext "extendedKeyUsage = critical, serverAuth"\
                -addext "subjectKeyIdentifier = hash"\
                -addext "subjectAltName = $san"
                if [ $? -ne 0 ]; then
                    echo "生成失败！"
                    cd ..
                    rm -rf "$DEFAULT_CERT_DIR"
                    exit 1
                fi
                sign_cert "$days"
                mk_chain_crt
                mk_chain_crl
                vertify_cert
                if [ $? -ne 0 ]; then
                    echo "生成的证书无效！"
                    exit 1
                fi
                echo "生成完成！请检查证书信息："
                output_cert
            ;;
            4)
                echo "---------生成VPN客户端证书---------"
                echo "请指定证书有效期（天）："
                read days
                input_san
                openssl req -config "$ssl_conf" -new -out request.csr\
                -addext "basicConstraints = critical, CA:FALSE"\
                -addext "keyUsage = critical, digitalSignature, keyAgreement"\
                -addext "extendedKeyUsage = critical, clientAuth"\
                -addext "subjectKeyIdentifier = hash"\
                -addext "subjectAltName = $san"
                if [ $? -ne 0 ]; then
                    echo "生成失败！"
                    cd ..
                    rm -rf "$DEFAULT_CERT_DIR"
                    exit 1
                fi
                sign_cert "$days"
                mk_chain_crt
                mk_chain_crl
                vertify_cert
                if [ $? -ne 0 ]; then
                    echo "生成的证书无效！"
                    exit 1
                fi
                echo "生成完成！请检查证书信息："
                output_cert
            ;;
            *)
                echo "输入错误！"
                exit 1
            ;;
        esac
    fi
fi
exit 0