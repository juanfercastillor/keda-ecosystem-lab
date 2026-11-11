package com.laboratorio.elasticity;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.Map;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api")
public class WorkloadController {

    private static final long MAX_WORK_MS = 10_000;

    private final String hostname = System.getenv().getOrDefault("HOSTNAME", "local");

    @GetMapping("/hello")
    public Map<String, Object> hello() {
        return Map.of(
                "message", "Hola desde elasticity-api",
                "pod", hostname);
    }

    /**
     * Simula una petición costosa: consume CPU durante {@code ms} milisegundos.
     * A mayor número de peticiones concurrentes, mayor uso de CPU por pod,
     * lo que permite a KEDA disparar el escalado horizontal.
     */
    @GetMapping("/work")
    public Map<String, Object> work(@RequestParam(defaultValue = "300") long ms) {
        long workMs = Math.clamp(ms, 0, MAX_WORK_MS);
        long start = System.nanoTime();
        long deadline = start + workMs * 1_000_000;

        MessageDigest digest = newDigest();
        long operations = 0;
        while (System.nanoTime() < deadline) {
            digest.update(("elasticity-lab-" + operations++).getBytes(StandardCharsets.UTF_8));
            digest.digest();
        }

        long elapsedMs = (System.nanoTime() - start) / 1_000_000;
        return Map.of(
                "pod", hostname,
                "requestedMs", workMs,
                "elapsedMs", elapsedMs,
                "operations", operations);
    }

    private static MessageDigest newDigest() {
        try {
            return MessageDigest.getInstance("SHA-256");
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }
}
