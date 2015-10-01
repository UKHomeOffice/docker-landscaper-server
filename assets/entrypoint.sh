#!/bin/bash

set -e

#If debug set execution follow and print out
#all environment variables
if [[ -n $DEBUG_ENTRYPOINT ]]; then
   set -x
   export
fi

#This is a handy pieces to wait for other services to come up 
if [[ -n $STARTUP_WAIT_TIME ]]; then
  printf "Delaying startup for $STARTUP_WAIT_TIME seconds"
  sleep $STARTUP_WAIT_TIME
fi

#Database
DB_LANDSCAPE_USER=landscape
DB_LANDSCAPE_PASS=${DB_LANDSCAPE_PASS:-password}
DB_HOST=${DB_HOST:-}
DB_PORT=${DB_PORT:-5432}
DB_USER=${DB_USER:-postgres}
DB_PASS=${DB_PASS:-password}
DB_NAME=${DB_NAME:-postgres}

#RMQ
RMQ_HOST=${RMQ_HOST:-}
RMQ_PORT=${RMQ_PORT:-5672}
RMQ_USER=${RMQ_USER:-guest}
RMQ_PASS=${RMQ_PASS:-guest}
RMQ_VHOST=${RMQ_VHOST:-/}

#If we have a linked postgres container setup the database
#environment to match that
if [[ -n ${POSTGRES_PORT_5432_TCP_ADDR} ]]; then
	DB_HOST=${DB_HOST:-${POSTGRES_PORT_5432_TCP_ADDR}}
	DB_PORT=${DB_PORT:-${POSTGRES_PORT_5432_TCP_PORT}}
	DB_USER=${DB_USER:-${POSTGRES_ENV_POSTGRES_USER}}
	DB_PASS=${DB_PASS:-${POSTGRES_ENV_POSTGRES_PASSWORD}}
fi

#Set postgres variables for commandline usage
PGHOST=${DB_HOST}
PGPORT=${DB_PORT}
export PGUSER=${DB_USER}
export PGPASSWORD=${DB_PASS}
PGNAME=${DB_NAME}

#Support additiona environment variables if in container
PGUSER=${PGUSER:-${POSTGRES_ENV_PGUSER}}
PGPASSWORD=${PGPASSWORD:-${POSTGRES_ENV_PGPASSWORD}}

PGUSER=${PGUSER:-${POSTGRES_ENV_USERNAME}}
PGPASSWORD=${PGPASSWORD:-${POSTGRES_ENV_PASSWORD}}

#If RMQ container is linked in then set that up
if [[ -n ${RABBITMQ_PORT_5672_TCP_ADDR} ]]; then
	RMQ_HOST=${RMQ_HOST:-${RABBITMQ_PORT_5672_TCP_ADDR}}
	RMQ_PORT=${RMQ_PORT:-${RABBITMQ_PORT_5672_TCP_PORT}}
	RMQ_USER=${RMQ_USER:-${RABBITMQ_ENV_ADMIN_USER}}
	RMQ_PASS=${RMQ_PASS:-${RABBITMQ_ENV_ADMIN_PASS}}
	RMQ_VHOST=${RMQ_VHOST:-${RABBITMQ_ENV_VHOST}}
fi

if [[ -z $DB_HOST ]]; then
	echo "ERROR: "
	echo "   Please configure the database connection"
	exit 1
fi

if [[ -z $RMQ_HOST ]]; then
	echo "ERROR: "
	echo "   Please configure the RMQ connection"
	exit 1
fi


appInit () {

  #Wait for the database server to become active
  prog=$(find /usr/lib/postgresql/ -name pg_isready)
  prog="${prog} -h ${DB_HOST} -p ${DB_PORT} -U ${DB_USER} -d ${DB_NAME} -t 1"
 
  timeout=60
  printf "Waiting for database server to become ready"
  while ! ${prog} >/dev/null 2>&1
  do
	timeout=$(expr $timeout - 1 )
	if [[ $timeout -eq 0 ]]; then
		printf "\nCount not connect to database server. Aborting...\n"
		exit 1
	fi
	printf "."
	sleep 1
  done

  #Update the config file to include all the relevant pieces
  sed -i 's,{{DB_LANDSCAPE_USER}},'"${DB_LANDSCAPE_USER}"',g' /etc/landscape/service.conf
  sed -i 's,{{DB_LANDSCAPE_PASS}},'"${DB_LANDSCAPE_PASS}"',g' /etc/landscape/service.conf
  sed -i 's,{{DB_USER}},'"${DB_USER}"',g' /etc/landscape/service.conf
  sed -i 's,{{DB_PASS}},'"${DB_PASS}"',g' /etc/landscape/service.conf
  sed -i 's,{{DB_HOST}},'"${DB_HOST}"',g' /etc/landscape/service.conf
  sed -i 's,{{DB_PORT}},'"${DB_PORT}"',g' /etc/landscape/service.conf

  sed -i 's,{{RMQ_HOST}},'"${RMQ_HOST}"',g' /etc/landscape/service.conf
  sed -i 's,{{RMQ_PORT}},'"${RMQ_PORT}"',g' /etc/landscape/service.conf
  sed -i 's,{{RMQ_USER}},'"${RMQ_USER}"',g' /etc/landscape/service.conf
  sed -i 's,{{RMQ_PASS}},'"${RMQ_PASS}"',g' /etc/landscape/service.conf
  sed -i 's,{{RMQ_VHOST}},'"${RMQ_VHOST}"',g' /etc/landscape/service.conf

  #Make sure permissions are correct on service.conf
  chmod 644 /etc/landscape/service.conf

  #Enable services for running
  sed -i 's,RUN_ALL="no",RUN_ALL="yes",g' /etc/default/landscape-server

}

startSyslog () {
  if ! pgrep rsyslogd 
  then
    printf "Starting rsyslogd\n"
    rsyslogd
  fi
}

appSchema () {
  appInit
  startSyslog
  printf "Running schema check\n"

  #Landscape does an annoying thing, if the landscape schema does not exist
  #it creates it and the landscape role with a new password and then
  #updates the config file inside the container with the new password.
  #This means you have no idea what the password is when a new container starts

  #Force creation of the landscape role with password we set so it doesn't get autoset
  prog=$(find /usr/lib/postgresql/ -name psql)
  psqlconn="${prog} -t -A -h ${DB_HOST} -p ${DB_PORT} -U ${DB_USER} -d ${DB_NAME} -w"
  if [[ "`${psqlconn} -c \"SELECT rolname FROM pg_roles where rolname='${DB_LANDSCAPE_USER}';\"`" == "" ]]; then
    printf "Creating landscape user\n"
    [[ "`${psqlconn} -c \"CREATE ROLE $DB_LANDSCAPE_USER with password '${DB_LANDSCAPE_PASS}' LOGIN;\"`" ]] && printf "User landscape created\n"
  fi

  setup-landscape-server
}

appStart () {
  appInit
  startSyslog

  #Do a schema create or check if flaggged to do it
  if [[ -n ${INITIALIZE_SCHEMA} ]]; then
    printf "Validating/creating database schema\n"
    appSchema
  fi

  printf "Starting landscape components\n"
  /etc/init.d/landscape-combo-loader start
  /etc/init.d/landscape-appserver start
  /etc/init.d/landscape-async-frontend start
  /etc/init.d/landscape-job-handler start
  /etc/init.d/landscape-msgserver start
  /etc/init.d/landscape-pingserver start
  /etc/init.d/landscape-api start
  /etc/init.d/landscape-juju-sync start
  /etc/init.d/landscape-package-upload start
  
  . /etc/default/landscape-server
  /opt/canonical/landscape/package-search &

  printf "Starting web proxy\n"
  . /etc/apache2/envvars
  mkdir -p /var/lock/apache2
  /usr/sbin/apache2ctl -DFOREGROUND

}

appHelp () {
	echo "Available options:"
	echo "  app:start        - Starts the landscape server ( default)"
	echo "  app:schema       - Initialize landscape server database schema or upgrade it, but don't start it"
	echo "  app:help         - Display the help"
}



#Running
case ${1} in
  app:start)
    appStart
    ;;
  app:schema)
    appSchema
    ;;
  app:help)
    appHelp
    ;;
  *)
    if [[ -x $1 ]]; then
      $1
    else
      prog=$(which $1)
      if [[ -n ${prog} ]] ; then
        shift 1
        $prog $@
      else
        appHelp
      fi
    fi
    ;;
esac

exit 0
