FROM python:3.7.2-alpine3.8
RUN mkdir /app
COPY requirements.txt /app/
WORKDIR /app
RUN pip install -r requirements.txt
CMD ["/finance/bin/docker-run.sh"]
