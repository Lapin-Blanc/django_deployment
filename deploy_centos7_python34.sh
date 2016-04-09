#/bin/bash

yum install -y epel-release
yum -y upgrade

###########################################################
# installation d'apache, python 3.4, virtualenv et mod_wsgi
yum -y install python34{,-devel,-setuptools} gcc httpd{,-devel} wget
easy_install pip
pip install virtualenv

# install latest mod_wsgi release at https://github.com/GrahamDumpleton/mod_wsgi/releases
if [ "$(httpd -t -D DUMP_MODULES | grep wsgi_module)" != "" ]; then
    echo "#############################"
    echo "mod_wsgi déjà installé"
    read -p "Appuyez sur une touche pour continuer"
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

    if [ "$(httpd -t -D DUMP_MODULES | grep wsgi_module)" != "" ]; then
        echo "#############################"
        echo "mod_wsgi installé avec succès"
        read -p "Appuyez sur une touche pour continuer"
    fi
fi
# mod_wsgi installed

# fin d'installation d'apache, python 3.4, virtualenv et mod_wsgi
#################################################################


#####################################
# début de la création d'utilisateur
VALID_USER_RE='^[a-zA-Z][a-zA-Z0-9_\-]{5,}$'

echo "###############################"
read -p "Nom pour l'utilisateur django : " DJANGO_USER

while [[ ! "$DJANGO_USER" =~ $VALID_USER_RE ]]
do
        echo "Le nom d'utilisateur doit faire au moins 5 caractères, être composé de lettres et de chiffres et commencer par une lettre"
        read -p "Nom pour l'utilisateur django : " DJANGO_USER
done

if [ "$(cut -d: -f1 /etc/passwd | grep $DJANGO_USER)" != "" ]; then 
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
    
    useradd $DJANGO_USER
    usermod -a -G $DJANGO_USER apache
    echo $DJANGO_USER:$PASSWORD | chpasswd
fi
# fin de la création de l'utilisateur
#####################################

#######################################
# début de la création du projet django
echo "#######################"
read -p "Nom du projet django : " DJANGO_PROJECT
if [ -d "/home/$DJANGO_USER/$DJANGO_PROJECT" ]; then
    echo "Ce projet existe déja"
else
    mkdir -v /home/$DJANGO_USER/$DJANGO_PROJECT
    cd /home/$DJANGO_USER/$DJANGO_PROJECT
    virtualenv -p /usr/bin/python3 "$DJANGO_PROJECT"_env
    source "$DJANGO_PROJECT"_env/bin/activate
    pip install django 
    django-admin startproject $DJANGO_PROJECT .
    sed -i "s/en-us/fr-be/" $DJANGO_PROJECT/settings.py
    sed -i "s/UTC/Europe\/Brussels/" $DJANGO_PROJECT/settings.py
    echo "STATIC_ROOT = os.path.join(BASE_DIR,'static/')" >> $DJANGO_PROJECT/settings.py
    ./manage.py makemigrations
    ./manage.py migrate
    ./manage.py createsuperuser
    ./manage.py collectstatic
    chown -R $DJANGO_USER:$DJANGO_USER /home/$DJANGO_USER/$DJANGO_PROJECT 
    chmod g+x /home/$DJANGO_USER
fi
# fin de la création du projet django
#####################################

#######################################################
# début de la configuration du virtual host pour apache
VALID_HOSTNAME_RE='^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9])\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\-]*[A-Za-z0-9])$'
echo "########################"
while [[ ! $VIRTUAL_HOST_DOMAIN =~ $VALID_HOSTNAME_RE ]]
do
        read -p "Nom de l'hôte virtuel : " VIRTUAL_HOST_DOMAIN
done

while [[ ! "$BASE_URL" =~ $VALID_USER_RE ]]
do
    read -p "Racine du site : " BASE_URL
done

sed -i "s/\(^STATIC_URL.*\)\(static.*\)$/\1$BASE_URL\/\2/" /home/fabien/SurveyProject/SurveyProject/settings.py

echo "<VirtualHost *:80>
    ServerAdmin webmaster@$VIRTUAL_HOST_DOMAIN
    ServerName $VIRTUAL_HOST_DOMAIN
    ErrorLog logs/$VIRTUAL_HOST_DOMAIN-error
    CustomLog logs/$VIRTUAL_HOST_DOMAIN-access common

    Alias /$BASE_URL/static/ /home/$DJANGO_USER/$DJANGO_PROJECT/static/
    <Directory /home/$DJANGO_USER/$DJANGO_PROJECT/static>
        Require all granted
    </Directory>

    <Directory /home/$DJANGO_USER/$DJANGO_PROJECT/$DJANGO_PROJECT>
        <Files wsgi.py>
            Require all granted
        </Files>
    </Directory>

    WSGIDaemonProcess $DJANGO_PROJECT user=$DJANGO_USER group=$DJANGO_USER python-path=/home/$DJANGO_USER/$DJANGO_PROJECT:/home/$DJANGO_USER/$DJANGO_PROJECT/"$DJANGO_PROJECT"_env/bin:/home/$DJANGO_USER/$DJANGO_PROJECT/"$DJANGO_PROJECT"_env/lib/python3.4/site-packages/
    WSGIProcessGroup $DJANGO_PROJECT
    WSGIScriptAlias /$BASE_URL /home/$DJANGO_USER/$DJANGO_PROJECT/$DJANGO_PROJECT/wsgi.py

</VirtualHost>" > /etc/httpd/conf.d/"$VIRTUAL_HOST_DOMAIN".conf

# règle pour selinux
chcon -R -t httpd_sys_rw_content_t /home/$DJANGO_USER
semanage fcontext -a -t httpd_sys_rw_content_t "/home/$DJANGO_USER(/.*)?"
systemctl start httpd
systemctl enable httpd
# fin de la configuration de l'hôte virtuel
###########################################
