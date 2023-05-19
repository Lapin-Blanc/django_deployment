#!/bin/bash
# déploiement de projet django sur serveur Debian 11

# Vérifier si l'utilisateur actuel est root
if [ "$EUID" -ne 0 ]
  then echo "Please run as root or use sudo"
  exit
fi

# Variables d'installation
DJANGO_PROJECT="gestion_fleu"
DJANGO_USER="$DJANGO_PROJECT"_user
DJANGO_GROUP="$DJANGO_USER"
PROJECT_REPO="https://git.techprog.be/fabien.toune/gestion_fleu.git"
DOMAIN="fleu.techprog.be"

# Nettoyage
function cleanup() {
    systemctl stop $DJANGO_PROJECT
    systemctl disable $DJANGO_PROJECT
    rm -rf /etc/systemd/system/$DJANGO_PROJECT.service
    rm -rf /etc/nginx/sites-enabled/$DOMAIN
    rm -rf /etc/nginx/sites-available/$DOMAIN
    rm -rf /var/opt/$DJANGO_PROJECT/media/
    rm -rf /var/cache/$DJANGO_PROJECT/static/ 
    rm -rf /var/www/$DOMAIN
    rm -rf /etc/opt/$DJANGO_PROJECT
    rm -rf /var/log/$DJANGO_PROJECT
    rm -rf /var/opt/$DJANGO_PROJECT
    rm -rf /opt/$DJANGO_PROJECT/venv
    deluser $DJANGO_USER
    rm -rf /opt/$DJANGO_PROJECT/
}

# if first argument is --cleanup, then cleanup and exit
if [ "$1" == "--cleanup" ]; then
    cleanup
    exit 0
fi

# Installation des dépendances
apt update && apt upgrade -y
apt install -y git python3-pip python3-venv virtualenvwrapper nginx-light

# Création des dossiers
mkdir /opt/$DJANGO_PROJECT
mkdir /etc/opt/$DJANGO_PROJECT
mkdir /var/www/$DOMAIN
mkdir -p /var/opt/$DJANGO_PROJECT
mkdir -p /var/opt/$DJANGO_PROJECT/media
mkdir -p /var/log/$DJANGO_PROJECT
mkdir -p /var/cache/$DJANGO_PROJECT/static

# Création de l'utilisateur système
adduser --system --home=/var/opt/$DJANGO_PROJECT \
    --no-create-home --disabled-password --group \
    --shell=/bin/bash $DJANGO_USER

# Ajustement des permissions
chown $DJANGO_USER /var/opt/$DJANGO_PROJECT/media
chown $DJANGO_USER /var/opt/$DJANGO_PROJECT
chown $DJANGO_USER /var/log/$DJANGO_PROJECT

chgrp $DJANGO_GROUP /etc/opt/$DJANGO_PROJECT
chmod u=rwx,g=rx,o= /etc/opt/$DJANGO_PROJECT

# Récupération du projet GIT
git clone $PROJECT_REPO /opt/$DJANGO_PROJECT/ || {
    echo 'git clone failed, exiting.'
    exit 1
}

# Création de l'environnement virtuel
virtualenv --system-site-packages --python=/usr/bin/python3 \
    /opt/$DJANGO_PROJECT/venv

# Installation des requirements
if [ -f /opt/$DJANGO_PROJECT/requirements.txt ]; then
    /opt/$DJANGO_PROJECT/venv/bin/pip install -r /opt/$DJANGO_PROJECT/requirements.txt
else
    echo 'requirements.txt not found, skipping pip install.'
fi

# Configuration du projet django
echo "from $DJANGO_PROJECT.settings import *

DEBUG = True
ALLOWED_HOSTS = ['$DOMAIN']
DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.sqlite3',
        'NAME': '/var/opt/$DJANGO_PROJECT/$DJANGO_PROJECT.db',
    }
}

STATIC_ROOT = '/var/cache/$DJANGO_PROJECT/static/'
STATIC_URL = '/static/'

MEDIA_ROOT = '/var/cache/$DJANGO_PROJECT/media/'
MEDIA_URL = '/media/'

" > /etc/opt/$DJANGO_PROJECT/settings.py

# Initialisation du projet
export PYTHONPATH=/etc/opt/$DJANGO_PROJECT:/opt/$DJANGO_PROJECT
export DJANGO_SETTINGS_MODULE=settings

su $DJANGO_USER -c \
    "/opt/"$DJANGO_PROJECT"/venv/bin/python \
    /opt/"$DJANGO_PROJECT"/manage.py makemigrations" \

su $DJANGO_USER -c \
    "/opt/"$DJANGO_PROJECT"/venv/bin/python \
    /opt/"$DJANGO_PROJECT"/manage.py migrate" \

/opt/$DJANGO_PROJECT/venv/bin/python \
    /opt/$DJANGO_PROJECT/manage.py collectstatic \

# Définition du superuser
echo "Enter superuser username:"
read DJANGO_SUPERUSER_USERNAME
export DJANGO_SUPERUSER_USERNAME=$DJANGO_SUPERUSER_USERNAME

echo "Enter password for django superuser:"
read -s DJANGO_SUPERUSER_PASSWORD
export DJANGO_SUPERUSER_PASSWORD=$DJANGO_SUPERUSER_PASSWORD \
export DJANGO_SUPERUSER_EMAIL=$DJANGO_SUPERUSER_USERNAME"@"$DOMAIN \

su $DJANGO_USER -c \
    "/opt/"$DJANGO_PROJECT"/venv/bin/python \
    /opt/"$DJANGO_PROJECT"/manage.py createsuperuser --noinput"

# Compilation des modules python
/opt/$DJANGO_PROJECT/venv/bin/python -m compileall \
    -x /opt/$DJANGO_PROJECT/venv/ /opt/$DJANGO_PROJECT

# /opt/$DJANGO_PROJECT/venv/bin/python -m compileall \
#     /etc/opt/$DJANGO_PROJECT

# Installation du projet comme service gunicorn
/opt/$DJANGO_PROJECT/venv/bin/pip install gunicorn

echo "[Unit]
Description=$DJANGO_PROJECT

[Service]
User=$DJANGO_USER
Group=$DJANGO_GROUP
Environment="PYTHONPATH=/etc/opt/$DJANGO_PROJECT:/opt/$DJANGO_PROJECT"
Environment="DJANGO_SETTINGS_MODULE=settings"
ExecStart=/opt/$DJANGO_PROJECT/venv/bin/gunicorn \
    --workers=4 \
    --log-file=/var/log/$DJANGO_PROJECT/gunicorn.log \
    --bind=127.0.0.1:8000 --bind=[::1]:8000 \
    $DJANGO_PROJECT.wsgi:application

[Install]
WantedBy=multi-user.target" > /etc/systemd/system/$DJANGO_PROJECT.service

systemctl start $DJANGO_PROJECT
systemctl enable $DJANGO_PROJECT

# Configuration du serveur virtuel nginx
echo "server {
        listen 80;
        listen [::]:80;
        server_name $DOMAIN;
        root /var/www/$DOMAIN/;
	location / {
    		proxy_pass http://localhost:8000;
    		proxy_set_header Host \$http_host;
    		proxy_redirect off;
    		proxy_set_header X-Forwarded-For \$remote_addr;
    		proxy_set_header X-Forwarded-Proto \$scheme;
    		client_max_body_size 20m;
	}
    	location /static/ {
        	alias /var/cache/$DJANGO_PROJECT/static/;
    	}
	location /media/ {
    		alias /var/opt/$DJANGO_PROJECT/media/;
	}

}" > /etc/nginx/sites-available/$DOMAIN

ln -s /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/

service nginx restart
