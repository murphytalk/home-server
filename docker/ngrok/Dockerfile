FROM alpine:latest as build
RUN apk update && apk upgrade && \
    apk add --no-cache unzip
ADD https://bin.equinox.io/c/4VmDzA7iaHb/ngrok-stable-linux-arm.zip ngrok.zip
RUN unzip ngrok.zip -d /bin && rm -f ngrok.zip

FROM alpine:latest
COPY --from=build /bin /bin
COPY ngrok.yml /root
COPY run.sh /bin

CMD ["/bin/run.sh"]
