package com.devops.sharedresources.dto;

import lombok.Builder;
import lombok.Getter;

@Builder @Getter
public class UserDto {
    private final String username;
    private final String email;
}
