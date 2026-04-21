FROM alpine:3.22.4

RUN apk add --no-cache python3 curl

COPY exporter.py /exporter.py

EXPOSE 8080

CMD ["python3", "/exporter.py"]
