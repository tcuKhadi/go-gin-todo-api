package events

import (
	"context"
	"encoding/json"
	"time"

	"github.com/segmentio/kafka-go"
)

type Event struct {
	Type      string      `json:"type"`
	Timestamp time.Time   `json:"timestamp"`
	Payload   interface{} `json:"payload"`
}

type Producer struct {
	writer *kafka.Writer
}

func NewProducer(brokerURL, topic string) *Producer {
	return &Producer{
		writer: &kafka.Writer{
			Addr:         kafka.TCP(brokerURL),
			Topic:        topic,
			Balancer:     &kafka.LeastBytes{},
			BatchTimeout: 10 * time.Millisecond,
		},
	}
}

func (p *Producer) Publish(ctx context.Context, key string, eventType string, payload interface{}) error {
	evt := Event{
		Type:      eventType,
		Timestamp: time.Now().UTC(),
		Payload:   payload,
	}

	bytes, err := json.Marshal(evt)
	if err != nil {
		return err
	}

	return p.writer.WriteMessages(ctx, kafka.Message{
		Key:   []byte(key),
		Value: bytes,
	})
}

func (p *Producer) Close() error {
	return p.writer.Close()
}
