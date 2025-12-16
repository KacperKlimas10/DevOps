package com.devops.storageservice.controller;

import com.devops.sharedresources.dto.FileUploadRequestDto;
import com.devops.sharedresources.dto.FileUploadResponseDto;
import lombok.RequiredArgsConstructor;
import com.devops.storageservice.service.StorageService;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.net.URISyntaxException;

@RestController
@RequestMapping("/api/storage")
@RequiredArgsConstructor
public class StorageController {

    private final StorageService storageService;

    @PostMapping("/file")
    ResponseEntity<FileUploadResponseDto> fileUploadRequest(@RequestBody FileUploadRequestDto fileUploadRequestDto) throws URISyntaxException {
        FileUploadResponseDto fileUploadResponseDto = storageService.fileUploadRequest(fileUploadRequestDto);
        return ResponseEntity
                .created(fileUploadResponseDto.getDownloadUrl().toURI())
                .body(fileUploadResponseDto);
    }
}