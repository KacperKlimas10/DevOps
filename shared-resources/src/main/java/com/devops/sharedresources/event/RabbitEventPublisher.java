package com.devops.sharedresources.event;

import org.springframework.amqp.AmqpException;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Component;

import java.util.Map;

@Slf4j
@Component("RabbitMQ")
@RequiredArgsConstructor
public class RabbitEventPublisher implements EventPublisher {

    private final RabbitTemplate rabbitTemplate;

    @Async
    @Override
    public void publish(Event event) {
        try {
            Map<String, String> configMap = eventPublishConfig(event);
            rabbitTemplate.convertAndSend(
                configMap.get("exchange"),
                configMap.get("routingKey"),
                event
            );
        } catch (AmqpException amqpException) {
            log.error("RabbitEventPublisher: ", amqpException.getCause());
        }
    }

    private Map<String, String> eventPublishConfig(Event event) {
        if (event.getClass().isAnnotationPresent(EventPublishConfig.class)) {
            return Map.of(
                "exchange", event.getClass().getAnnotation(EventPublishConfig.class).exchange(),
                "routingKey", event.getClass().getAnnotation(EventPublishConfig.class).routingKey()
            );
        } else throw new AmqpException("RabbitMQ event mapping failed!");
    }
}