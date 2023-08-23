FROM node:20-alpine

WORKDIR /usr/src/app

RUN apk add --update --no-cache \
    make \
    g++ \
    jpeg-dev \
    cairo-dev \
    giflib-dev \
    pango-dev \
    libtool \
    autoconf \
    automake

COPY package*.json /usr/src/app

RUN npm install
RUN npm install -g nodemon

COPY . .

EXPOSE 80

# Set default value for COMPOSE_RUN
ARG COMPOSE_RUN=false

# Wait for dynamodb is running via docker-compose (local)
CMD sh -c 'if [ "$COMPOSE_RUN" = "true" ]; then until nc -z dynamodb 8000; do sleep 1; done; nodemon -L --watch /usr/src/app app.js; else npm start; fi'