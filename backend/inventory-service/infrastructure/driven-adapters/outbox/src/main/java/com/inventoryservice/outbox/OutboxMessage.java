package com.inventoryservice.outbox;

import org.springframework.data.annotation.Id;
import org.springframework.data.relational.core.mapping.Column;
import org.springframework.data.relational.core.mapping.Table;

import java.time.Instant;

@Table("outbox")
public class OutboxMessage {
    @Id
    private Long id;
    @Column("aggregate_type") private String aggregateType;
    @Column("aggregate_id") private String aggregateId;
    @Column("event_type") private String eventType;
    private String topic;
    private String payload;
    private String status;
    @Column("created_at") private Instant createdAt;
    @Column("published_at") private Instant publishedAt;

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }
    public String getAggregateType() { return aggregateType; }
    public void setAggregateType(String v) { this.aggregateType = v; }
    public String getAggregateId() { return aggregateId; }
    public void setAggregateId(String v) { this.aggregateId = v; }
    public String getEventType() { return eventType; }
    public void setEventType(String v) { this.eventType = v; }
    public String getTopic() { return topic; }
    public void setTopic(String v) { this.topic = v; }
    public String getPayload() { return payload; }
    public void setPayload(String v) { this.payload = v; }
    public String getStatus() { return status; }
    public void setStatus(String v) { this.status = v; }
    public Instant getCreatedAt() { return createdAt; }
    public void setCreatedAt(Instant v) { this.createdAt = v; }
    public Instant getPublishedAt() { return publishedAt; }
    public void setPublishedAt(Instant v) { this.publishedAt = v; }
}
