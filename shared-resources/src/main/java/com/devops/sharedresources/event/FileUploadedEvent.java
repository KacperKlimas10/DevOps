package com.devops.sharedresources.event;

import lombok.Builder;
import lombok.Getter;
import java.net.URL;
import java.util.UUID;

@Builder @Getter
@EventPublishConfig(exchange = "storage.events", routingKey = "file.uploaded")
public class FileUploadedEvent extends Event {
    private final URL putSignedUrl;
    private final URL getSignedUrl;
    private final UUID fileUUID;
    private final String fileName;
}