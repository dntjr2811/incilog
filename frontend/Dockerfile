FROM node:20-alpine

WORKDIR /app

# 社内プロキシ対応: SSL検証スキップ
RUN npm config set strict-ssl false

COPY package.json package-lock.json* ./
RUN npm install

COPY . .

EXPOSE 3000

CMD ["npm", "start"]
