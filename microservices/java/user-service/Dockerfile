FROM maven AS builder

WORKDIR /build

COPY . .

RUN mvn clean package -DskipTests

FROM eclipse-temurin:25-jre-ubi10-minimal AS development

WORKDIR /app

RUN microdnf -y update && microdnf -y install curl && \
    groupadd -g 1001 webservice && \
    useradd --no-create-home -u 1001 -g 1001 webservice && \
    chown -R webservice:webservice /app

COPY --from=builder build/target/*.jar webservice.jar

EXPOSE 8080

USER webservice

ENTRYPOINT ["java", "-jar", "webservice.jar"]
CMD []

FROM eclipse-temurin:25-jre-ubi10-minimal AS release

WORKDIR /app

RUN groupadd -g 1001 webservice && \
    useradd --no-create-home -u 1001 -g 1001 webservice && \
    chown -R webservice:webservice /app

COPY --from=builder build/target/*.jar webservice.jar

EXPOSE 8080

USER webservice

ENTRYPOINT ["java", "-jar", "webservice.jar"]
CMD []