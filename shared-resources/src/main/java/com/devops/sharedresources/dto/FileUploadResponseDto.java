package com.devops.sharedresources.dto;

import lombok.Builder;
import lombok.Getter;
import java.net.URL;
import java.util.UUID;

@Builder @Getter
public class FileUploadResponseDto {
    private final UUID fileUUID;
    private final URL downloadUrl;
    private final URL uploadUrl;
}
