package com.devops.userservice.service;

import com.devops.userservice.model.UserModel;
import lombok.RequiredArgsConstructor;
import com.devops.userservice.repository.UserRepository;
import org.springframework.stereotype.Service;

@Service
@RequiredArgsConstructor
public class UserService {

    private final UserRepository userRepository;

    public void createUser(String username, String email) {
        userRepository.save(
                UserModel.builder()
                        .username(username)
                        .email(email)
                        .build()
        );
    }
}
