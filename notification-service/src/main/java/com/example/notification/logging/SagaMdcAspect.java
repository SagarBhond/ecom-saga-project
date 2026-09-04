package com.example.notification.logging;

import com.example.notification.event.SagaEvent;
import org.aspectj.lang.ProceedingJoinPoint;
import org.aspectj.lang.annotation.Around;
import org.aspectj.lang.annotation.Aspect;
import org.slf4j.MDC;
import org.springframework.stereotype.Component;

/**
 * Puts the saga's business ID (order ID) into MDC as "sagaId" for the
 * duration of every @KafkaListener method, so every log line produced while
 * handling that event — in THIS service and, since every service does the
 * same thing, in every OTHER service that touches the same order — can be
 * grepped/filtered on one value.
 *
 * This is deliberately separate from correlationId (see CorrelationIdFilter):
 * correlationId is scoped to a single synchronous HTTP request/thread.
 * sagaId survives the async hop through Kafka (different thread, different
 * JVM, different service) because it's a business field carried inside the
 * SagaEvent payload itself, not a thread-local header.
 *
 * Implemented as one AOP aspect instead of editing every listener method by
 * hand, so new @KafkaListener methods get this for free.
 */
@Aspect
@Component
public class SagaMdcAspect {

    private static final String MDC_KEY = "sagaId";

    @Around("@annotation(org.springframework.kafka.annotation.KafkaListener)")
    public Object populateSagaId(ProceedingJoinPoint joinPoint) throws Throwable {
        String sagaId = extractSagaId(joinPoint.getArgs());
        if (sagaId == null) {
            return joinPoint.proceed();
        }
        try {
            MDC.put(MDC_KEY, sagaId);
            return joinPoint.proceed();
        } finally {
            MDC.remove(MDC_KEY);
        }
    }

    private String extractSagaId(Object[] args) {
        for (Object arg : args) {
            if (arg instanceof SagaEvent sagaEvent) {
                return sagaEvent.getSagaId();
            }
        }
        return null; // e.g. @DltHandler methods that take a raw String — logged as-is
    }
}
