package com.devops.sharedresources.dto;

import lombok.Builder;
import lombok.Getter;
import java.util.UUID;

@Builder @Getter
public class FileUploadRequestDto {
    private final UUID ownerUUID;
    private final String filename;
    private final String contentType;
    private final String category;
    private final String operationType;
}
