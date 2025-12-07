package com.parcelplatform.userservice.event;

import com.parcelplatform.sharedresources.event.Event;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.stereotype.Component;

@Component
@Slf4j
@RequiredArgsConstructor
public class RabbitEventListener {

    @RabbitListener(queues = "storage-user")
    public void consume(Event event) {
        System.out.println(event.getEventUUID() + "\n" + event.getLocalDateTime());
    }
}
