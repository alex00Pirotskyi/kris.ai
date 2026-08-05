export class BoundedTranscript {
  constructor(limitBytes = 8 * 1024 * 1024) {
    if (!Number.isSafeInteger(limitBytes) || limitBytes < 4096 || limitBytes > 64 * 1024 * 1024) {
      throw new Error('invalid_transcript_budget');
    }
    this.limitBytes = limitBytes;
    this.chunks = [];
    this.bytes = 0;
    this.cursor = 0;
    this.truncated = false;
  }

  append(data) {
    let bytes = Buffer.from(data);
    const absoluteStart = this.cursor;
    this.cursor += bytes.length;
    if (bytes.length >= this.limitBytes) {
      bytes = bytes.subarray(bytes.length - this.limitBytes);
      this.chunks = [{ start: this.cursor - bytes.length, bytes }];
      this.bytes = bytes.length;
      this.truncated = true;
      return;
    }
    this.chunks.push({ start: absoluteStart, bytes });
    this.bytes += bytes.length;
    while (this.bytes > this.limitBytes && this.chunks.length) {
      const overflow = this.bytes - this.limitBytes;
      const first = this.chunks[0];
      if (first.bytes.length <= overflow) {
        this.chunks.shift();
        this.bytes -= first.bytes.length;
      } else {
        first.bytes = first.bytes.subarray(overflow);
        first.start += overflow;
        this.bytes -= overflow;
      }
      this.truncated = true;
    }
  }

  read(fromCursor = 0) {
    if (!Number.isSafeInteger(fromCursor) || fromCursor < 0) {
      throw new Error('invalid_transcript_cursor');
    }
    const availableFrom = this.chunks.at(0)?.start ?? this.cursor;
    const data = Buffer.concat(
      this.chunks
        .filter((chunk) => chunk.start + chunk.bytes.length > fromCursor)
        .map((chunk) => chunk.bytes.subarray(Math.max(0, fromCursor - chunk.start))),
    );
    return {
      fromCursor,
      availableFrom,
      nextCursor: this.cursor,
      truncatedBefore: fromCursor < availableFrom,
      data,
    };
  }
}
