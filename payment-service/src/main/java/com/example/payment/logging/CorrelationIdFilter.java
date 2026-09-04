package com.example.payment.logging;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.ServletRequest;
import jakarta.servlet.ServletResponse;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.slf4j.MDC;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.UUID;

/**
 * Assigns every inbound HTTP request a correlation ID and puts it in the
 * SLF4J MDC so it shows up on EVERY log line produced while handling that
 * request (controller, service, outbound RestTemplate/WebClient calls) —
 * without having to pass it through method signatures by hand.
 *
 * - Reads "X-Correlation-ID" from the incoming request if the caller (e.g.
 *   an upstream service, API gateway, or Postman) already supplied one.
 * - Otherwise generates a fresh UUID.
 * - Echoes it back on the response header so callers can log/display it too.
 * - Always clears the MDC in a finally block — MDC is thread-local and
 *   threads are reused from a pool, so leaving stale values behind would
 *   leak one request's correlation ID into another request handled later
 *   on the same thread.
 *
 * NOTE: this only covers the synchronous HTTP request thread. The Kafka
 * saga (outbox poller → Kafka → @KafkaListener in another service) runs on
 * different threads/JVMs entirely, so it is correlated separately using the
 * business sagaId (see SagaEventListener) rather than this HTTP-scoped ID.
 */
@Component
@Order(Integer.MIN_VALUE) // run before everything else so all downstream logging sees it
public class CorrelationIdFilter extends OncePerRequestFilter {

    public static final String HEADER_NAME = "X-Correlation-ID";
    public static final String MDC_KEY = "correlationId";

    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                     HttpServletResponse response,
                                     FilterChain filterChain) throws ServletException, IOException {
        String correlationId = request.getHeader(HEADER_NAME);
        if (correlationId == null || correlationId.isBlank()) {
            correlationId = UUID.randomUUID().toString();
        }
        try {
            MDC.put(MDC_KEY, correlationId);
            response.setHeader(HEADER_NAME, correlationId);
            filterChain.doFilter(request, response);
        } finally {
            MDC.remove(MDC_KEY);
        }
    }
}
