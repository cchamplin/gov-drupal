#!/bin/bash

# usage: file_env VAR [DEFAULT]
#    ie: file_env 'XYZ_DB_PASSWORD' 'example'
# (will allow for "$XYZ_DB_PASSWORD_FILE" to fill in the value of
#  "$XYZ_DB_PASSWORD" from a file, especially for Docker's secrets feature)
file_env() {
	local var="$1"
	local fileVar="${var}_FILE"
	local def="${2:-}"
	if [ "${!var:-}" ] && [ "${!fileVar:-}" ]; then
		echo >&2 "error: both $var and $fileVar are set (but are exclusive)"
		exit 1
	fi
	local val="$def"
	if [ "${!var:-}" ]; then
		val="${!var}"
	elif [ "${!fileVar:-}" ]; then
		val="$(< "${!fileVar}")"
	fi
	export "$var"="$val"
	unset "$fileVar"
}

file_env 'DOCROOT'
if [ ! -z "$DOCROOT" ] && ! grep -q "^DocumentRoot \"$DOCROOT\"" /etc/httpd/conf/httpd.conf ; then
	sed -i "s#/var/www/public#$DOCROOT#g" /etc/httpd/conf/httpd.conf
fi
echo "export DOCROOT='$DOCROOT'" > /etc/profile.d/docroot.sh

# Make sure we're not confused by old, incompletely-shutdown httpd
# context after restarting the container.  httpd won't start correctly
# if it thinks it is already running.
rm -rf /run/httpd/* /tmp/httpd*

# Perform git pull
if [ -d "/var/application/www" ]; then
  if [ -v GIT_BRANCH ]; then
    git --git-dir=/var/application git checkout $GIT_BRANCH
    git --git-dir=/var/application git pull origin $GIT_BRANCH
  fi
else
  if [ -v GIT_URL ]; then
    git clone $GIT_URL /var/application
    if [ -d "/var/application/www" ]; then
      if [ -v GIT_BRANCH ]; then
        git --git-dir=/var/application git checkout $GIT_BRANCH
        git --git-dir=/var/application git pull origin $GIT_BRANCH
      fi
      if [ -d "/var/www/public" ]; then
        mv /var/www/public /var/www/public_orig
      fi
      ln -s /var/application/www /var/www/public
    fi
  fi
fi

# Symlink appropriate directories into the drupal document root
# It would be good to have a more dynamic way to do this
# to support other use cases
if [ -d "/var/application/www/sites/default" ]; then
  if [ -d "/mnt/public_files" ]; then
     ln -s /mnt/public_files /var/application/www/sites/default/files
  fi
  if [ -d "/mnt/config" ]; then
    if [ -f "/mnt/config/settings.php" ]; then
      ln -s /mnt/config/settings.php /var/application/www/sites/default
    fi
  fi
fi

exec /usr/sbin/apachectl -DFOREGROUND
