import gleam/option.{type Option, None, Some}

/// Classification of where an event originated.
///
/// Closed sum for known transports plus `CustomSource(String)` as the
/// escape hatch for ecosystem-external sources (e.g. internal protocols
/// or experimental integrations).
pub type SourceKind {
  ScheduleSource
  FileSystemSource
  ManualSource
  WebhookSource
  QueueSource
  SignalSource
  HttpSource
  CloudEventSource
  CustomSource(String)
}

/// Identification of the producer that emitted an event.
///
/// `id` is the stable identifier of the producer (e.g. plan id, watch
/// path, webhook endpoint). `name` is an optional human-readable label.
pub type Source {
  Source(kind: SourceKind, id: String, name: Option(String))
}

/// Build a `Source` with no human-readable label. Use `with_name` to
/// attach one if your transport/observability needs it.
pub fn new(kind kind: SourceKind, id id: String) -> Source {
  Source(kind: kind, id: id, name: None)
}

/// Attach an optional human-readable label to a source.
pub fn with_name(source source: Source, name name: String) -> Source {
  Source(..source, name: Some(name))
}

/// Shortcut for `new(ScheduleSource, id)`.
pub fn schedule(id id: String) -> Source {
  new(kind: ScheduleSource, id: id)
}

/// Shortcut for `new(FileSystemSource, id)`.
pub fn file_system(id id: String) -> Source {
  new(kind: FileSystemSource, id: id)
}

/// Shortcut for `new(ManualSource, id)`.
pub fn manual(id id: String) -> Source {
  new(kind: ManualSource, id: id)
}

/// Shortcut for `new(WebhookSource, id)`.
pub fn webhook(id id: String) -> Source {
  new(kind: WebhookSource, id: id)
}

/// Shortcut for `new(QueueSource, id)`.
pub fn queue(id id: String) -> Source {
  new(kind: QueueSource, id: id)
}

/// Shortcut for `new(SignalSource, id)`.
pub fn signal(id id: String) -> Source {
  new(kind: SignalSource, id: id)
}

/// Shortcut for `new(HttpSource, id)`.
pub fn http(id id: String) -> Source {
  new(kind: HttpSource, id: id)
}

/// Shortcut for `new(CloudEventSource, id)`.
pub fn cloud_event(id id: String) -> Source {
  new(kind: CloudEventSource, id: id)
}

/// Shortcut for `new(CustomSource(kind), id)` — the escape hatch for
/// ecosystem-external producers.
pub fn custom(kind kind: String, id id: String) -> Source {
  new(kind: CustomSource(kind), id: id)
}

/// Stable string label for a `SourceKind`, used for routing tables,
/// metrics, and structured logs.
pub fn kind_to_string(kind: SourceKind) -> String {
  case kind {
    ScheduleSource -> "schedule"
    FileSystemSource -> "file_system"
    ManualSource -> "manual"
    WebhookSource -> "webhook"
    QueueSource -> "queue"
    SignalSource -> "signal"
    HttpSource -> "http"
    CloudEventSource -> "cloud_event"
    CustomSource(name) -> "custom:" <> name
  }
}
