package com.devops.sharedresources.event;

import lombok.Getter;
import java.io.Serializable;
import java.time.LocalDateTime;
import java.util.UUID;

@Getter
public abstract class Event implements Serializable {
    private final UUID eventUUID = UUID.randomUUID();
    private final String localDateTime = LocalDateTime.now().toString();
}