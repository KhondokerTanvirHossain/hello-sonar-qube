# Hello SonarQube

This project sets up a SonarQube instance using Docker Compose for code quality analysis and static code review. It uses PostgreSQL as the database backend.

## Prerequisites

Before running this project, ensure you have the following installed on your system:
- [Docker](https://www.docker.com/)
- [Docker Compose](https://docs.docker.com/compose/)

## Setup Instructions

### 1. Clone the Repository

Clone this repository to your local machine:

```bash
git clone <repository-url>
cd hello-sonar-qube
```

### 2. Start the Services

Run the following command to start SonarQube and PostgreSQL:

```bash
docker-compose up -d
```

### 3. Access SonarQube

Once the services are running, you can access the SonarQube dashboard in your browser at:

```bash
http://localhost:9000
```

### 4. Login to SonarQube

Use the default credentials log in:

```bash
Username: admin
Password: admin
```

You will be prompted to change the password after the first login.

### 5. Analyze Your Code

Configure your project in SonarQube.
Use the SonarScanner to analyze your code and send the results to the SonarQube server.
Configuration
Environment Variables
The following environment variables are used in the docker-compose.yml file:

```bash
SONAR_JDBC_URL: The JDBC URL for the PostgreSQL database.
SONAR_JDBC_USERNAME: The username for the PostgreSQL database.
SONAR_JDBC_PASSWORD: The password for the PostgreSQL database.
Volumes
sonarqube_db_data: Stores PostgreSQL data persistently.
```

## Troubleshooting

### Common Issues

1. Elasticsearch Errors:

Ensure sufficient disk space is available.
Allocate enough memory to Elasticsearch by setting SONAR_ES_JAVAOPTS in the docker-compose.yml file:
Database Charset Issues:

```bash
environment:
  SONAR_ES_JAVAOPTS: "-Xms512m -Xmx512m"
```

Ensure the PostgreSQL database is created with UTF-8 encoding.
Logs
To view logs for debugging:

```bash
docker logs -f sonarqube
docker logs -f sonarqube_db
```

## Stopping the Services

To stop the services, run:

```bash
docker-compose down
```