package com.devops.storageservice.storage;

import io.awspring.cloud.s3.S3Template;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.net.URL;
import java.time.Duration;

@Component("R2Storage")
@RequiredArgsConstructor
public class R2StorageProvider implements StorageRepository {

    private final S3Template s3Template;

    @Value("${env.aws.bucket.name}")
    private String bucketName;
    private static final int DURATION_MINUTES = 5;

    @Override
    public URL getSignedUrl(String filename) {
        return s3Template.createSignedGetURL(
                bucketName,
                filename,
                Duration.ofMinutes(DURATION_MINUTES)
        );
    }

    @Override
    public URL putSignedUrl(String filename) {
        return s3Template.createSignedPutURL(
                bucketName,
                filename,
                Duration.ofMinutes(DURATION_MINUTES)
        );
    }
}
