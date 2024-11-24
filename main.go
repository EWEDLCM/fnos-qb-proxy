package main

import (
    "bytes"
    "context"
    "flag"
    "fmt"
    "io"
    "log"
    "net"
    "net/http"
    "net/http/httputil"
    "net/url"
    "os"
    "os/exec"
    "regexp"
    "strings"
    "strconv"
    "time"
)

// fetchAria2Token retrieves the token from the Aria2 process.
func fetchAria2Token() (string, error) {
    // Execute command "ps aux | grep [a]ria2c"
    cmd := exec.Command("bash", "-c", "ps aux | grep [a]ria2c")
    output, err := cmd.Output()
    if err != nil {
        return "", fmt.Errorf("exec command %s: %w", cmd.String(), err)
    }

    // Parse output (like --rpc-secret=xxx) to get token
    re := regexp.MustCompile(`--rpc-secret=(\S+)`)
    matches := re.FindStringSubmatch(string(output))
    if len(matches) > 1 {
        return matches[1], nil
    }

    return "", fmt.Errorf("no aria2c process found with a token")
}

// watchAria2Token watches for changes in the Aria2 token.
func watchAria2Token(ch chan string) {
    ticker := time.NewTicker(1 * time.Second)
    for range ticker.C {
        token, err := fetchAria2Token()
        if err != nil {
            fmt.Printf("fetch aria2c token: %v\n", err)
            continue
        }

        ch <- token
    }
}

// readPortFromConfig reads the port from the Aria2 configuration file.
func readPortFromConfig(configFile string) (int, error) {
    content, err := os.ReadFile(configFile)
    if err != nil {
        return 0, fmt.Errorf("failed to read config file %s: %w", configFile, err)
    }

    re := regexp.MustCompile(`--rpc-listen-port=(\d+)`)
    matches := re.FindStringSubmatch(string(content))
    if len(matches) > 1 {
        port, err := strconv.Atoi(matches[1])
        if err != nil {
            return 0, fmt.Errorf("invalid port number in config file %s: %w", configFile, err)
        }
        return port, nil
    }

    return 0, fmt.Errorf("no valid port number found in config file %s", configFile)
}

// checkSocketFileExists checks if the socket file exists.
func checkSocketFileExists(socketPath string) error {
    _, err := os.Stat(socketPath)
    if err != nil {
        if os.IsNotExist(err) {
            return fmt.Errorf("socket file %s does not exist", socketPath)
        }
        return fmt.Errorf("error checking socket file %s: %v", socketPath, err)
    }

    return nil
}

func main() {
    user := os.Getenv("USER")
    if user == "" {
        log.Fatalf("environment variable USER is not set")
    }

    defaultUDS := fmt.Sprintf("/home/%s/aria2.sock", user)
    uds := flag.String("uds", defaultUDS, "Aria2 unix domain socket(uds) path")
    debug := flag.Bool("debug", false, "enable debug logging")
    config := flag.String("config", "", "path to the configuration file")
    expectedToken := flag.String("token", "", "if not set, any token will be accepted")

    flag.Parse()

    if *config == "" {
        log.Fatalf("configuration file path must be provided")
    }

    port, err := readPortFromConfig(*config)
    if err != nil {
        log.Fatalf("failed to read port from config file: %v", err)
    }

    // Print the username and the socket path for debugging
    fmt.Printf("Current user: %s\n", user)
    fmt.Printf("Socket path: %s\n", *uds)
    fmt.Printf("Listening on port: %d\n", port)

    // Check if the socket file exists
    if err := checkSocketFileExists(*uds); err != nil {
        log.Fatalf("failed to start: %v", err)
    }

    token, err := fetchAria2Token()
    if err != nil {
        log.Fatalf("fetch aria2c token: %v", err)
    }

    debugf := func(format string, args ...interface{}) {
        if *debug {
            fmt.Printf(format, args...)
        }
    }

    fmt.Printf("proxy running on port %d\n", port)

    ch := make(chan string)
    go watchAria2Token(ch)
    go func() {
        for newToken := range ch {
            if newToken == token {
                continue
            }

            token = newToken
            fmt.Printf("new token: %s\n", token)
        }
    }()

    targetURL, _ := url.Parse(fmt.Sprintf("http://file://%s", *uds))
    proxy := httputil.NewSingleHostReverseProxy(targetURL)
    proxy.Transport = &http.Transport{
        DialContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
            conn, err := net.Dial("unix", *uds)
            if err != nil {
                log.Printf("failed to connect to socket %s: %v", *uds, err)
                return nil, err
            }
            return conn, nil
        },
    }

    proxy.Director = func(r *http.Request) {
        debugf("request: %v\n", r.URL.Path)
        r.URL.Scheme = "http"
        r.URL.Host = fmt.Sprintf("file://%s", *uds)
        r.Host = fmt.Sprintf("file://%s", *uds)

        body := []byte{}
        if r.Body != nil {
            body, _ = io.ReadAll(r.Body)
            r.Body = io.NopCloser(bytes.NewBuffer(body))
        }

        r.ParseForm()
        if strings.Contains(r.URL.Path, "/jsonrpc") && *expectedToken != "" {
            // Add token to the request body
            bodyStr := string(body)
            if !strings.Contains(bodyStr, `"token":"`) {
                bodyStr = fmt.Sprintf(`{"token":"%s"}`, *expectedToken) + bodyStr
                body = []byte(bodyStr)
            }
            r.Header.Set("Content-Length", fmt.Sprintf("%d", len(body)))
            r.ContentLength = int64(len(body))
            r.Body = io.NopCloser(bytes.NewBuffer(body))
        } else {
            // Ensure the original body is used if not modifying it
            r.Header.Set("Content-Length", fmt.Sprintf("%d", len(body)))
            r.ContentLength = int64(len(body))
            r.Body = io.NopCloser(bytes.NewBuffer(body))
        }

        r.Header.Del("Referer")
        r.Header.Del("Origin")
    }

    err = http.ListenAndServe(fmt.Sprintf(":%d", port), proxy)
    if err != nil {
        log.Fatalf("listen and serve: %v", err)
    }
}
