FROM python:3.7.2-alpine3.8 as build
RUN apk update && apk upgrade && \
    apk add --no-cache git
RUN mkdir /app && mkdir /install
WORKDIR /app
RUN git clone https://github.com/murphytalk/anki-sync-server.git
WORKDIR /app/anki-sync-server
RUN  git submodule update --init && rm -fr .git* && rm -fr anki-bundled/.git*
WORKDIR /app/anki-sync-server/anki-bundled
RUN sed -i '/# Packaged commands/,$d' anki/sound.py && \
    sed -i '/^pyaudio/d' requirements.txt
RUN pip install --install-option="--prefix=/install" -r requirements.txt && \
    pip install --install-option="--prefix=/install" webob

FROM python:3.7.2-alpine3.8
RUN mkdir /app
COPY --from=build /app /app
COPY --from=build /install /usr/local
WORKDIR /app/anki-sync-server/anki-bundled
CMD ["/bin/sh", "/app/anki-sync-server/start.sh"]
