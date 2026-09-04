package com.example.notification.config;

import com.example.notification.exception.ServiceUnavailableException;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.client.ClientHttpResponse;
import org.springframework.web.client.DefaultResponseErrorHandler;
import org.springframework.web.client.RestTemplate;
import org.springframework.http.client.ClientHttpRequestInterceptor;
import org.slf4j.MDC;
import com.example.notification.logging.CorrelationIdFilter;

import java.io.IOException;
import java.util.Collections;

@Configuration
public class RestTemplateConfig {

    @Bean
    public RestTemplate restTemplate() {
        RestTemplate restTemplate = new RestTemplate();
        restTemplate.setErrorHandler(new DefaultResponseErrorHandler() {
            @Override
            public void handleError(ClientHttpResponse response) throws IOException {
                int statusCode = response.getRawStatusCode();
                if (statusCode >= 500) {
                    throw new ServiceUnavailableException("Service returned error " + statusCode);
                }
                super.handleError(response);
            }
        });

        // Propagate the current request's correlation ID onto every outbound
        // call this RestTemplate makes, so the callee's logs can be joined
        // with the caller's logs on X-Correlation-ID.
        restTemplate.setInterceptors(Collections.singletonList(correlationIdInterceptor()));

        return restTemplate;
    }

    private ClientHttpRequestInterceptor correlationIdInterceptor() {
        return (request, body, execution) -> {
            String correlationId = MDC.get(CorrelationIdFilter.MDC_KEY);
            if (correlationId != null) {
                request.getHeaders().add(CorrelationIdFilter.HEADER_NAME, correlationId);
            }
            return execution.execute(request, body);
        };
    }
}

