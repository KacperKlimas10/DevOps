package com.devops.userservice.controller;

import com.devops.userservice.dto.UserDto;
import lombok.RequiredArgsConstructor;
import com.devops.userservice.service.UserService;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/user")
@RequiredArgsConstructor
public class UserController {

    private final UserService userService;

    @GetMapping
    public ResponseEntity<String> helloUser() {
        return ResponseEntity
                .ok()
                .body("Hello from user-service after second Test CD/CD and Helm");
    }

    @PostMapping
    public ResponseEntity<Void> createUser(@RequestBody UserDto userDto) {
        userService.createUser(userDto.getUsername(), userDto.getEmail());
        return ResponseEntity
                .noContent()
                .build();
    }
}
