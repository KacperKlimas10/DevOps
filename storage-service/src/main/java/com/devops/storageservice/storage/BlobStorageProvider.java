package com.devops.storageservice.storage;

import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

import java.net.URL;

@Component("BlobStorage")
@RequiredArgsConstructor
public class BlobStorageProvider implements StorageRepository {
    @Override
    public URL getSignedUrl(String filename) {
        return null;
    }

    @Override
    public URL putSignedUrl(String filename) {
        return null;
    }
}
