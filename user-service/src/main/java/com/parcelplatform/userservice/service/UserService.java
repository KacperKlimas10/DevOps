package com.parcelplatform.userservice.service;

import lombok.RequiredArgsConstructor;
import com.parcelplatform.sharedresources.event.EventPublisher;
import com.parcelplatform.userservice.model.UserModel;
import com.parcelplatform.userservice.repository.UserRepository;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.stereotype.Service;

@Service
@RequiredArgsConstructor
public class UserService {

    private final UserRepository userRepository;

    @Qualifier("RabbitMQ")
    private final EventPublisher eventPublisher;

    public void createUser(String username, String email) {
        userRepository.save(
                UserModel.builder()
                        .username(username)
                        .email(email)
                        .build()
        );
    }
}
