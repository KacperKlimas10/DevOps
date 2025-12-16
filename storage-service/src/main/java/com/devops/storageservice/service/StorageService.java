package com.devops.storageservice.service;

import com.devops.sharedresources.dto.FileUploadRequestDto;
import com.devops.sharedresources.dto.FileUploadResponseDto;
import lombok.RequiredArgsConstructor;
import com.devops.storageservice.storage.StorageRepository;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.stereotype.Service;

import java.util.UUID;

@Service
@RequiredArgsConstructor
public class StorageService {

    @Qualifier("BlobStorage")
    private final StorageRepository storageRepository;

    public FileUploadResponseDto fileUploadRequest(FileUploadRequestDto fileUploadRequestDto) {
        return FileUploadResponseDto.builder()
                .fileUUID(UUID.randomUUID())
                .downloadUrl(storageRepository.getSignedUrl(fileUploadRequestDto.getFilename()))
                .uploadUrl(storageRepository.putSignedUrl(fileUploadRequestDto.getFilename()))
                .build();
    }
}
