FROM node:18-alpine

WORKDIR /usr/src/app

# Copy dependency files
COPY chaincode/package*.json ./

# Install dependencies (including fabric-contract-api)
RUN npm install --production

# Copy the rest of the chaincode source files
COPY chaincode/ .

# CCaaS requires starting the chaincode server explicitly
EXPOSE 9999
CMD [ "npm", "start" ]
