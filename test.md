# Twain Test Document

This is a **test file** for the *Twain* markdown viewer.

## Features

- Read-only viewer
- Multiple windows
- Light and dark mode
- Fast rendering

## Code Block

```swift
struct ContentView: View {
    var body: some View {
        Text("Hello, Twain!")
    }
}
```

## Table

| Feature | Status |
|---------|--------|
| Rendering | Working |
| Multi-window | Working |
| Dark mode | Working |

## Blockquote

> This is a blockquote to verify styling.

---

## More Code Blocks

```python
def fibonacci(n):
    # Generate fibonacci sequence
    a, b = 0, 1
    for _ in range(n):
        yield a
        a, b = b, a + b

print(list(fibonacci(10)))
```

```javascript
async function fetchData(url) {
    const response = await fetch(url);
    if (!response.ok) {
        throw new Error(`HTTP error: ${response.status}`);
    }
    return response.json();
}
```

```bash
#!/bin/bash
for file in *.md; do
    echo "Processing $file..."
    twain "$file"
done
```

---

End of test.
