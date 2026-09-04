package com.example.order.controller;

import com.example.order.dto.CreateOrderRequest;
import com.example.order.entity.Order;
import com.example.order.repository.OrderRepository;
import com.example.order.service.OrderService;
import com.example.order.service.ServiceHealthClient;
import io.github.resilience4j.circuitbreaker.CircuitBreaker;
import io.github.resilience4j.circuitbreaker.CircuitBreakerRegistry;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import static com.example.order.config.CircuitBreakerConfig.*;

@RestController
@RequestMapping("/api/orders")
@RequiredArgsConstructor
@Slf4j
public class OrderController {

    private final OrderService orderService;
    private final OrderRepository orderRepository;
    private final CircuitBreakerRegistry circuitBreakerRegistry;
    private final ServiceHealthClient serviceHealthClient;

    @PostMapping
    public ResponseEntity<Order> create(@RequestBody CreateOrderRequest req) {
        log.info("POST /api/orders customerId={} productId={} quantity={}",
                req.getCustomerId(), req.getProductId(), req.getQuantity());
        Order order = orderService.createOrder(req);
        log.info("Order {} accepted, status={}", order.getId(), order.getStatus());
        return ResponseEntity.ok(order);
    }

    @GetMapping("/{id}")
    public ResponseEntity<Order> get(@PathVariable String id) {
        log.debug("GET /api/orders/{}", id);
        return orderRepository.findById(UUID.fromString(id))
                .map(ResponseEntity::ok)
                .orElseGet(() -> {
                    log.warn("Order {} not found", id);
                    return ResponseEntity.notFound().build();
                });
    }

    @GetMapping
    public List<Order> all() {
        List<Order> orders = orderRepository.findAll();
        log.debug("GET /api/orders → {} order(s)", orders.size());
        return orders;
    }

    @GetMapping("/circuit-breakers")
    public ResponseEntity<Map<String, Object>> circuitBreakerStatus() {
        log.debug("GET /api/orders/circuit-breakers");
        Map<String, Object> result = new LinkedHashMap<>();

        for (String name : List.of(
                KAFKA_PUBLISHER_BREAKER,
                INVENTORY_SERVICE_BREAKER,
                PAYMENT_SERVICE_BREAKER,
                NOTIFICATION_SERVICE_BREAKER)) {

            CircuitBreaker cb = circuitBreakerRegistry.circuitBreaker(name);
            CircuitBreaker.Metrics m = cb.getMetrics();

            Map<String, Object> info = new LinkedHashMap<>();
            info.put("state", cb.getState().name());
            info.put("failureRate", m.getFailureRate() + " %");
            info.put("slowCallRate", m.getSlowCallRate() + " %");
            info.put("bufferedCalls", m.getNumberOfBufferedCalls());
            info.put("failedCalls", m.getNumberOfFailedCalls());
            info.put("successfulCalls", m.getNumberOfSuccessfulCalls());
            info.put("notPermittedCalls", m.getNumberOfNotPermittedCalls());

            result.put(name, info);
        }

        return ResponseEntity.ok(result);
    }

    @GetMapping("/services/health")
    public ResponseEntity<Map<String, Object>> servicesHealth() {
        log.debug("GET /api/orders/services/health");
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("inventory", serviceHealthClient.checkInventoryHealth());
        result.put("payment", serviceHealthClient.checkPaymentHealth());
        result.put("notification", serviceHealthClient.checkNotificationHealth());
        return ResponseEntity.ok(result);
    }
}