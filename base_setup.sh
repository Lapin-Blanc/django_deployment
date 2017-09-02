#!/bin/bash

yum -y install epel-release
yum upgrade
yum -y install vim wget git policycoreutils

echo "set autoindent
set expandtab
set ts=4
set sw=4
set bg=dark
map <F7> :tabp<CR>
map <F7> :tabn<CR>" >> /etc/vimrc

read -p "Port pour sshd : " SSH_PORT
sed -i "s/^#Port.*/Port $SSH_PORT/"  /etc/ssh/sshd_config
semanage port -a -t ssh_port_t -p tcp $SSH_PORT
systemctl restart sshd

cat << EOF > /etc/profile.d/custom_prompt.sh
if [ \$(id -u) -eq 0 ];
then # vous êtes root, invite en bleu
    export PS1="\[\e[00;36m\]\A\[\e[0m\]\[\e[00;37m\] \[\e[0m\]\[\e[00;34m\]\u\[\e[0m\]\[\e[00;33m\]@\[\e[0m\]\[\e[00;37m\]\h \[\e[0m\]\[\e[00;32m\]\w\[\e[0m\]\[\e[00;37m\] \[\e[0m\]\[\e[00;33m\]\$\[\e[0m\]\[\e[00;37m\] \[\e[0m\]"
else # si vous êtes utilisateur normal, invite en rouge
    export PS1="\[\e[00;36m\]\A\[\e[0m\]\[\e[00;37m\] \[\e[0m\]\[\e[00;31m\]\u\[\e[0m\]\[\e[00;33m\]@\[\e[0m\]\[\e[00;37m\]\h \[\e[0m\]\[\e[00;32m\]\w\[\e[0m\]\[\e[00;37m\] \[\e[0m\]\[\e[00;33m\]\$\[\e[0m\]\[\e[00;37m\] \[\e[0m\]"
fi
EOF

sed -i "s/#\(set bell-style .*\)/\1/" /etc/inputrc

read -p "Utilisateur GIT : " GIT_USER
read -p "Email GIT : " GIT_EMAIL
git config --global user.name "$GIT_USER"
git config --global user.email "$GIT_EMAIL"
git config --global credential.helper store
