FROM python:3.7.3-alpine3.9
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
RUN pip install -r requirements.txt && \
    pip install webob

CMD ["/bin/sh", "/app/start.sh"]
