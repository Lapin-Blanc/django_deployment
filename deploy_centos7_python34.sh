#/bin/bash

read -p "Voulez-vous mettre à jour le système ? [y/N] " YN
if [ "$YN" == "y" ]; then
    yum install -y epel-release
    yum -y upgrade
    ###########################################################
    # installation d'apache, python 3.4, virtualenv et mod_wsgi
    yum -y groupinstall "Development Tools"
    yum -y install python34{,-devel,-setuptools} httpd{,-devel} wget
    easy_install-3.4 pip
    pip install virtualenv
fi
YN=""

systemctl stop httpd
# install latest mod_wsgi release at https://github.com/GrahamDumpleton/mod_wsgi/releases
if [ "$(httpd -t -D DUMP_MODULES | grep wsgi_module)" != "" ]; then
    echo "#############################"
    echo "mod_wsgi déjà installé"
fi

read -p "Voulez-vous (ré)installer mod_wsgi ? [y/N] " YN
if [ "$YN" == "y" ]; then
    # on force malgré tout la recompilation de mod_wsgi en cas de changement des sources apache, kernel, etc.
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
    else
        echo "#############################"
        echo "Problème lors de l'installatin de mod_wsgi"
        read -p "Appuyez sur une touche pour continuer"
    fi
    # mod_wsgi installed
fi
YN=""

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
    read -p "Voulez-vous réinitialiser son profil ? [y/N] " YN
    if [ "$YN" == "y" ]; then
        userdel -f -Z $DJANGO_USER
        groupdel $DJANGO_USER
        grep -rl "$DJANGO_USER" /etc/httpd/conf.d/ | xargs rm -i
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
        # Utilisateur réinitialisé
    fi
    YN=""
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

cd "/home/$DJANGO_USER"
# fin de la création de l'utilisateur
#####################################

#######################################
# début de la création du projet django
echo "#######################"
read -p "Nom du projet django : " DJANGO_PROJECT

# Création de l'environnement virtuel
if [ -d "$DJANGO_PROJECT"_env ]; then
    echo "L'environnement virtuel existe déjà"
    read -p "Voulez vous le recréer ? [y/N] " YN
    if [ "$YN" == "y" ]; then
        echo "suppression de l'environnement virtuel"
        rm -fr "$DJANGO_PROJECT"_env
        echo "création de l'environnement virtuel"
        virtualenv -p /usr/bin/python3 "$DJANGO_PROJECT"_env
        source "$DJANGO_PROJECT"_env/bin/activate
        pip install django
    else
        source "$DJANGO_PROJECT"_env/bin/activate
    # TODO détecter un problème à l'activation de l'environnement virtuel
    # TODO vérifier ici que Django est bien présent, sinon, le réinstaller
    fi
    YN=""
else
    echo "création de l'environnement virtuel"
    virtualenv -p /usr/bin/python3 "$DJANGO_PROJECT"_env
    source "$DJANGO_PROJECT"_env/bin/activate
    pip install django
fi
# Fin de la création de l'environnement virtuel
############

# Création du project
if [ -d "$DJANGO_PROJECT" ]; then
    echo "Ce projet existe déja"
    read -p "Voulez vous le réinitialiser ? [y/N] " YN
    if [ "$YN" == "y" ]; then
        echo "suppression du projet"
        rm -fr "$DJANGO_PROJECT"
        grep -rl "$DJANGO_PROJECT" /etc/httpd/conf.d/ | xargs rm -i
    fi
    YN=""
fi
if [ ! -d "$DJANGO_PROJECT" ]; then
    django-admin startproject $DJANGO_PROJECT
    cd $DJANGO_PROJECT
    sed -i "s/en-us/fr-be/" $DJANGO_PROJECT/settings.py
    sed -i "s/UTC/Europe\/Brussels/" $DJANGO_PROJECT/settings.py
    echo "STATIC_ROOT = os.path.join(BASE_DIR,'static/')" >> $DJANGO_PROJECT/settings.py
    echo "MEDIA_URL = '/media/'" >> $DJANGO_PROJECT/settings.py
    echo "MEDIA_ROOT = os.path.join(BASE_DIR,'media/')" >> $DJANGO_PROJECT/settings.py
    ./manage.py makemigrations
    ./manage.py migrate
    ./manage.py createsuperuser
    ./manage.py collectstatic
fi
# Ajustement des permissions
chown -R $DJANGO_USER:$DJANGO_USER "/home/$DJANGO_USER"
chmod g+x "/home/$DJANGO_USER"
# fin de la création du projet django
#####################################

#######################################################
# début de la configuration du virtual host pour apache
read -p "Voulez-vous (re)configurer apache pour le projet ? [y/N] " YN
if [ "$YN" == "y" ]; then
    VALID_HOSTNAME_RE='^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9])\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\-]*[A-Za-z0-9])$'
    echo "########################"
    while [[ ! $VIRTUAL_HOST_DOMAIN =~ $VALID_HOSTNAME_RE ]]
    do
            read -p "Nom de l'hôte virtuel : " VIRTUAL_HOST_DOMAIN
    done

    sed -i "s/^DEBUG = True/DEBUG = False/" /home/$DJANGO_USER/$DJANGO_PROJECT/$DJANGO_PROJECT/settings.py
    sed -i "s/^ALLOWED_HOSTS.*$/ALLOWED_HOSTS = ['$VIRTUAL_HOST_DOMAIN']/" /home/$DJANGO_USER/$DJANGO_PROJECT/$DJANGO_PROJECT/settings.py

    echo "<VirtualHost *:80>
        ServerAdmin webmaster@$VIRTUAL_HOST_DOMAIN
        ServerName $VIRTUAL_HOST_DOMAIN
        ErrorLog logs/$VIRTUAL_HOST_DOMAIN-error
        CustomLog logs/$VIRTUAL_HOST_DOMAIN-access common

        Alias /media/ /home/$DJANGO_USER/$DJANGO_PROJECT/media/
        <Directory /home/$DJANGO_USER/$DJANGO_PROJECT/media>
            Require all granted
        </Directory>

        Alias /static/ /home/$DJANGO_USER/$DJANGO_PROJECT/static/
        <Directory /home/$DJANGO_USER/$DJANGO_PROJECT/static>
            Require all granted
        </Directory>

        <Directory /home/$DJANGO_USER/$DJANGO_PROJECT/$DJANGO_PROJECT>
            <Files wsgi.py>
                Require all granted
            </Files>
        </Directory>

        WSGIDaemonProcess $DJANGO_PROJECT user=$DJANGO_USER group=$DJANGO_USER python-path=/home/$DJANGO_USER/$DJANGO_PROJECT:/home/$DJANGO_USER/"$DJANGO_PROJECT"_env/bin:/home/$DJANGO_USER/"$DJANGO_PROJECT"_env/lib/python3.4/site-packages/
        WSGIProcessGroup $DJANGO_PROJECT
        WSGIScriptAlias / /home/$DJANGO_USER/$DJANGO_PROJECT/$DJANGO_PROJECT/wsgi.py

    </VirtualHost>" > /etc/httpd/conf.d/"$VIRTUAL_HOST_DOMAIN".conf
    # fin de la configuration de l'hôte virtuel
    ###########################################fi
fi
YN=""

# règle pour selinux
echo "Ajustement des permissins SELinux"
chcon -R -t httpd_sys_rw_content_t /home/$DJANGO_USER
semanage fcontext -a -t httpd_sys_rw_content_t "/home/$DJANGO_USER(/.*)?"

systemctl start httpd
systemctl enable httpd
echo "Fin de la procédure de déploiement"

