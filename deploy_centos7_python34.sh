#/bin/bash

yum install -y epel-release
yum -y upgrade

###########################################################
# installation d'apache, python 3.4, virtualenv et mod_wsgi
yum -y install python34{,-devel,-setuptools} gcc httpd{,-devel} wget
pip install virtualenv

# install latest mod_wsgi release at https://github.com/GrahamDumpleton/mod_wsgi/releases
if [ "$(httpd -t -D DUMP_MODULES | grep wsgi_module)" != "" ]; then
    echo "mod_wsgi déjà installé"
else
    mkdir mod_wsgi_src
    pushd mod_wsgi_src
    wget https://github.com/GrahamDumpleton/mod_wsgi/archive/4.5.1.tar.gz
    tar xvzf *.tar.gz
    cd mod_wsgi*
    ./configure --with-python=/usr/bin/python3
    make && make install
    echo "LoadModule wsgi_module /usr/lib64/httpd/modules/mod_wsgi.so" > /etc/httpd/conf.modules.d/10-wsgi.conf 
    popd
    rm -fr mod_wsgi_src
    systemctl start httpd
    systemctl enable httpd

    if [ "$(httpd -t -D DUMP_MODULES | grep wsgi_module)" != "" ]; then
        echo "mod_wsgi installé avec succès"
    fi
fi
# mod_wsgi installed

# fin d'installation d'apache, python 3.4, virtualenv et mod_wsgi
#################################################################


#####################################
# début de la création d'utilisateur
VALID_USER_RE='^[a-zA-Z][a-zA-Z0-9_\-]{5,}$'

if [ "$DJANGOUSER" == "" ]; then
    read -p "Nom pour l'utilisateur django : " DJANGOUSER
fi

echo "1- $DJANGOUSER"

while [[ ! "$DJANGOUSER" =~ $VALID_USER_RE ]]
do
        echo "Le nom d'utilisateur doit faire au moins 5 caractères, être composé de lettres et de chiffres et commencer par une lettre"
        read -p "Nom pour l'utilisateur django : " DJANGOUSER
done

if [ "$(cut -d: -f1 /etc/passwd | grep $DJANGOUSER)" != "" ]; then 
    echo "L'utilisateur existe déja"
else
    while [ -z $PASSWORD ]
    do
        read -s -p "$(echo -e "Mot de passe : ")" PASS1
        read -s -p "$(echo -e "\nMot de passe (vérification): ")" PASS2
        while [ "$PASS1" != "$PASS2" ]
        do
            echo -e "\nles mots de passe ne concordent pas..."
            read -s -p "$(echo -e "Mot de passe : ")" PASS1
            read -s -p "$(echo -e "\nMot de passe (vérification): ")" PASS2
        done
        PASSWORD=$PASS1
        echo -e "\n"
    done
    
    useradd $DJANGOUSER
    echo $DJANGOUSER:$PASSWORD | chpasswd
fi
# fin de la création de l'utilisateur
#####################################

# début de la création du projet django
#######################################

