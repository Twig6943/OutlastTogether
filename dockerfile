FROM python:3.13-slim

WORKDIR /app
COPY server.py .

EXPOSE 7777
CMD ["python3", "server.py", "--headless"]