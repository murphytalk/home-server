FROM python:3.7.2-alpine3.8 as build
RUN apk update && apk upgrade && \
    apk add --no-cache && apk add build-base && apk add libffi-dev && \
    apk add libxml2-dev && apk add libxslt-dev && apk add openssl-dev
RUN mkdir /app
COPY requirements.txt /app/
WORKDIR /app
RUN pip install --install-option="--prefix=/install" -r requirements.txt

FROM python:3.7.2-alpine3.8
RUN apk update && apk upgrade && \
    apk add --no-cache && apk add libffi && apk add libxml2 && apk add libxslt && \
    apk add openssl-dev
COPY --from=build /install /usr/local
CMD ["/bot/docker-run.sh"]
