# Ubuntu LandScape Docker Container

[![Build Status](https://travis-ci.org/UKHomeOffice/docker-landscape-server.svg?branch=master)](https://travis-ci.org/UKHomeOffice/docker-landscape-server)

This container runs the Ubuntu landscape server components

#Requirements

- Landscape requires a postgres 9.3/9.4 server with plpython and the debversion modules installed
- A rabbitmq server is also required as the message bus between the various components

#TLS

There is a placeholer certificate in the files/certs directory which gets added to the container and used by apache for the SSL endpoint.

This has a common name of 'landscape-server'.
This should be replaced with a valid certificate and key

#Running locally

There is a docker compose file which will bring up a landscape server,
this will bring up the landscape server on port 80/443 on your docker host
```
docker-compose build
docker-compose up
```

It does the following:
## Postgres database server
Create a postgres container based off of the official 9.4 version with plpython and debversion installed

```
docker build -t postgres .
docker run -d --name postgres -e POSTGRES_PASSWORD=password postgres
```

## Rabbitmq server
Create a rabbitmq container that will be linked in, which has the management module enables so you can 
access it via a web console

```
docker run -d --name rabbitmq -p 15672:15672 rabbitmq:3-management
```

## Landscape container creation
Then it build the landscape container, this container is based on ubuntu:14.04, this will link the postgres container into the landscape container and use that, if you have an external postgres instance you would just set the variables that are required

```
docker build -t landscape-server
docker run -d --link postgres:postgres --link rabbitmq:rabbitmq -e INITIALIZE_SCHEMA=yes -e DB_USER=postgres -e DB_PASS=password -e DB_LANDSCAPE_PASS=password -p 80:80 -p 443:443 landscape-server
```

### Valid commands for the landscape container
- app:schema - This will create the landscape user and schema but not start the application
- app:start - This starts the application, this is also the default action

#Variables that can be set

| Variable             | Default   | Usage  |
| -------------------- | --------- | ------ |
| STARTUP_WAIT_TIME    | empty     | Wait number of seconds before starting process, useful for waiting for other services to come up |
| INITIALIZE_SCHEMA    | empty     | If set this will create the database schema or confirm it is valid |
| DB_HOST              | empty     | The postgres server hostname |
| DB_PORT              | 5432      | The postgres server port |
| DB_LANDSCAPE_PASS    | password  | The landscape user password |
| DB_USER              | landscape | The postgres super user, this user is used for schema creation|
| DB_PASS              | landscape | The postgres super user password |
| DB_NAME              | postgres  | The default database name for testing connectivity |
| RMQ_HOST             | empty     | The rabbitmq server hostname |
| RMQ_PORT             | 5672      | The rabbitmq server amqp port |
| RMQ_USER             | guest     | The rabbitmq user |
| RMQ_PASS             | guest     | The rabbitmq password |
| RMQ_VHOST            | default   | The vhost to be used by the message broker |
