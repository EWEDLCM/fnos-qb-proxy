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

func fetchQbPassword() (string, error) {
    // exec command "ps aux | grep [q]bittorrent-nox"
    cmd := exec.Command("bash", "-c", "ps aux | grep [q]bittorrent-nox")
    output, err := cmd.Output()
    if err != nil {
        return "", fmt.Errorf("exec command %s: %w", cmd.String(), err)
    }

    // parse output(likes --webui-password=xxx) to get password
    re := regexp.MustCompile(`--webui-password=(\S+)`)
    matches := re.FindStringSubmatch(string(output))
    if len(matches) > 1 {
        return matches[1], nil
    }

    return "", fmt.Errorf("no qbittorrent-nox process found")
}

func watchQbPassword(ch chan string) {
    ticker := time.NewTicker(1 * time.Second)
    for range ticker.C {
        password, err := fetchQbPassword()
        if err != nil {
            fmt.Printf("fetch qbittorrent-nox password: %v\n", err)
            continue
        }

        ch <- password
    }
}

func readPortFromConfig(configFile string) (int, error) {
    content, err := os.ReadFile(configFile)
    if err != nil {
        return 0, fmt.Errorf("failed to read config file %s: %w", configFile, err)
    }

    re := regexp.MustCompile(`port=(\d+)`)
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

    defaultUDS := fmt.Sprintf("/home/%s/qbt.sock", user)
    uds := flag.String("uds", defaultUDS, "qBittorrent unix domain socket(uds) path")
    debug := flag.Bool("debug", false, "enable debug logging")
    config := flag.String("config", "", "path to the configuration file")
    expectedPassword := flag.String("password", "", "if not set, any password will be accepted")

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

    password, err := fetchQbPassword()
    if err != nil {
        log.Fatalf("fetch qbittorrent-nox password: %v", err)
    }

    debugf := func(format string, args ...interface{}) {
        if *debug {
            fmt.Printf(format, args...)
        }
    }

    fmt.Printf("proxy running on port %d\n", port)

    ch := make(chan string)
    go watchQbPassword(ch)
    go func() {
        for newPassword := range ch {
            if newPassword == password {
                continue
            }

            password = newPassword
            fmt.Printf("new password: %s\n", password)
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
        if strings.Contains(r.URL.Path, "/api/v2/auth/login") {
            outPassword := password
            if *expectedPassword != "" {
                parts := strings.Split(string(body), "&")
                debugf("parts: %v\n", parts)
                for _, part := range parts {
                    if strings.HasPrefix(part, "password=") {
                        inputPassword := strings.TrimPrefix(part, "password=")
                        if inputPassword != *expectedPassword {
                            outPassword = ""
                            break
                        }
                    }
                }
            }

            body = []byte(fmt.Sprintf("username=admin&password=%s", outPassword))
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
