// Bounded, standalone feasibility probe, NOT a new JavaScript API/framework.
// Includes the locked MiniRacer V8 implementation UNCHANGED. No Ruby linkage.
// Only attach original logger callbacks, evaluate owned cached processor source,
// call_await("emberVersion"), low-memory notification and disposal are exposed.
#include MINI_RACER_SOURCE
#include <condition_variable>
#include <mutex>
#include <thread>
#include <chrono>
#include <fstream>
#include <sstream>
#include <stdexcept>
#include <sys/stat.h>
#include <unistd.h>
#include <dirent.h>

struct Context {
    State *state = nullptr;
    std::string source, version, error, locales_json, messages_json;
    bool messageformat = false, strict = true;
    std::vector<uint8_t> callback_reply;
    std::mutex lock;
    std::condition_variable wake;
    std::thread worker;
    bool done = false, ready = false, stop = false, call = false, replied = false, callback = false, timed_out = false;
    size_t calls = 0;
    size_t callbacks = 0;
};
int single_threaded; // Set ONLY from actual configuration supplied by owned caller.
extern "C" void v8_get_flags(char **p, size_t *n) {
    *p = single_threaded ? strdup("--single_threaded") : nullptr;
    *n = *p ? strlen(*p) + 1 : 0;
}

static std::string string_value(State *s, v8::Local<v8::Value> value) {
    v8::String::Utf8Value text(s->isolate, value);
    return *text ? std::string(*text, text.length()) : std::string();
}
static std::vector<uint8_t> serialize(State *s, v8::Local<v8::Value> value) {
    v8::ValueSerializer ser(s->isolate);
    ser.WriteHeader();
    if (!ser.WriteValue(s->context, value).FromMaybe(false))
        throw std::runtime_error("native probe serialization failed");
    auto result = ser.Release();
    std::vector<uint8_t> bytes(result.first, result.first + result.second);
    free(result.first);
    return bytes;
}
static std::vector<uint8_t> arguments(State *s, const std::vector<v8::Local<v8::Value>>& values) {
    auto array = v8::Array::New(s->isolate, values.size());
    for (size_t i = 0; i < values.size(); ++i) array->Set(s->context, i, values[i]).Check();
    return serialize(s, array);
}
static v8::Local<v8::String> text_value(State *s, const std::string& text) {
    return v8::String::NewFromUtf8(s->isolate, text.data(), v8::NewStringType::kNormal, text.size()).ToLocalChecked();
}
extern "C" void v8_reply(Context *c, const uint8_t *p, size_t n) {
    if (n == 0) return;
    if (n == 1 && p[0] == 'c') { c->callback = true; return; }
    if (n == 1) { c->error = "native V8 termination reply"; return; }
    auto s = c->state;
    v8::HandleScope scope(s->isolate);
    v8::ValueDeserializer des(s->isolate, p, n);
    if (!des.ReadHeader(s->context).FromMaybe(false)) { c->error = "native V8 reply header"; return; }
    v8::Local<v8::Value> value;
    if (!des.ReadValue(s->context).ToLocal(&value)) { c->error = "native V8 reply value"; return; }
    if (c->callback) {
        c->callback = false;
        if (!value->IsArray()) { c->error = "native logger callback shape"; return; }
        auto args = value.As<v8::Array>();
        auto id = args->Get(s->context, args->Length() - 1).ToLocalChecked();
        int index = id->Int32Value(s->context).FromMaybe(-1);
        if (index < 0 || index > 2 || args->Length() != 2) { c->error = "unadmitted native host callback"; return; }
        auto message = string_value(s, args->Get(s->context, 0).ToLocalChecked());
        if (message.size() > 16384) { c->error = "unbounded native log callback"; return; }
        fprintf(stderr, "owned-asset-vm logger[%d]: %s\n", index, message.c_str());
        c->callbacks++;
    } else if (value->IsString()) {
        auto error = string_value(s, value); // attach response is err or empty.
        if (!error.empty()) c->error = error;
    } else if (value->IsArray()) {
        auto result = value.As<v8::Array>();
        auto error = string_value(s, result->Get(s->context, 1).ToLocalChecked());
        if (!error.empty()) c->error = error;
        auto output = result->Get(s->context, 0).ToLocalChecked();
        if (output->IsString()) c->version = string_value(s, output);
    } else c->error = "unadmitted native V8 reply";
}
extern "C" void v8_roundtrip(Context *c, const uint8_t **p, size_t *n) {
    auto bytes = serialize(c->state, v8::Null(c->state->isolate)); // original logger proc returns nil
    c->callback_reply.assign(1, 'c');
    c->callback_reply.insert(c->callback_reply.end(), bytes.begin(), bytes.end());
    *p = c->callback_reply.data(); *n = c->callback_reply.size();
}
extern "C" void v8_dispatch(Context *c) { c->error = "unexpected nested native command"; }
extern "C" void v8_thread_main(Context *c, State *s) {
    {
        std::lock_guard<std::mutex> guard(c->lock);
        c->state = s;
    }
    c->wake.notify_all();
    try {
        for (int i = 0; !c->messageformat && i < 3; ++i) {
            const char *names[] = {"rails.logger.info", "rails.logger.warn", "rails.logger.error"};
            auto bytes = arguments(s, {text_value(s, names[i]), v8::Int32::New(s->isolate, i)});
            v8_attach(s, bytes.data(), bytes.size());
            if (!c->error.empty()) throw std::runtime_error(c->error);
        }
        std::vector<uint8_t> bytes;
        if (c->messageformat) {
            v8::Local<v8::Value> packet;
            if (!v8::JSON::Parse(s->context, text_value(s, c->source)).ToLocal(&packet) || !packet->IsArray())
                throw std::runtime_error("invalid owned MessageFormat source packet");
            auto sources = packet.As<v8::Array>();
            if (sources->Length() != 3) throw std::runtime_error("unadmitted MessageFormat source count");
            for (uint32_t i = 0; i < sources->Length(); ++i) {
                auto item = sources->Get(s->context, i).ToLocalChecked();
                if (!item->IsArray() || item.As<v8::Array>()->Length() != 2) throw std::runtime_error("invalid owned MessageFormat source member");
                auto pair = item.As<v8::Array>();
                auto name = pair->Get(s->context, 0).ToLocalChecked();
                auto source = pair->Get(s->context, 1).ToLocalChecked();
                if (!name->IsString() || !source->IsString()) throw std::runtime_error("non-string MessageFormat source member");
                bytes = arguments(s, {name, source});
                v8_eval(s, bytes.data(), bytes.size());
                if (!c->error.empty()) throw std::runtime_error(c->error);
            }
        } else {
            bytes = arguments(s, {text_value(s, "asset-processor.js"), text_value(s, c->source)});
            v8_eval(s, bytes.data(), bytes.size());
        }
        if (!c->error.empty()) throw std::runtime_error(c->error);
        if (!c->messageformat) v8_low_memory_notification(s); // actual AssetProcessor lifecycle
        {
            std::lock_guard<std::mutex> guard(c->lock);
            c->ready = true;
        }
        c->wake.notify_all();
        bool issued_idle_gc = false;
        for (;;) {
            {
                std::unique_lock<std::mutex> guard(c->lock);
                if (!c->wake.wait_for(guard, std::chrono::milliseconds(2000), [&] { return c->call || c->stop; })) {
                    if (!issued_idle_gc && !c->messageformat) { v8_low_memory_notification(s); issued_idle_gc = true; }
                    continue;
                }
                if (c->stop) break;
                c->call = false;
            }
            c->version.clear();
            if (c->messageformat) {
                v8::Local<v8::Value> locales, messages;
                if (!v8::JSON::Parse(s->context, text_value(s, c->locales_json)).ToLocal(&locales) ||
                    !v8::JSON::Parse(s->context, text_value(s, c->messages_json)).ToLocal(&messages) ||
                    !((locales->IsArray() || locales->IsString())) || !((messages->IsObject() && !messages->IsArray()) || messages->IsString()))
                    throw std::runtime_error("invalid owned MessageFormat input shape");
                bytes = arguments(s, {text_value(s, "compileMessageFormat"), locales, messages, v8::Boolean::New(s->isolate, c->strict)});
                v8_call(s, bytes.data(), bytes.size());
            } else {
                bytes = arguments(s, {text_value(s, "emberVersion")});
                v8_call_await(s, bytes.data(), bytes.size());
            }
            if (single_threaded && !c->messageformat) v8_low_memory_notification(s); // original AssetProcessor.v8_call
            issued_idle_gc = false;
            c->calls++;
            if (!c->error.empty()) throw std::runtime_error(c->error);
            if (c->version.empty() || c->version.size() > (c->messageformat ? 16 * 1024 * 1024 : 128)) throw std::runtime_error("non-string/unbounded original VM result");
            {
                std::lock_guard<std::mutex> guard(c->lock);
                c->replied = true;
            }
            c->wake.notify_all();
        }
    } catch (const std::exception& error) { c->error = error.what(); }
    {
        std::lock_guard<std::mutex> guard(c->lock);
        c->state = nullptr;
        c->done = true;
    }
    c->wake.notify_all();
    // Upstream v8_thread_init now destroys original State/contexts/isolate.
}
static int own_thread_count() {
    DIR *directory = opendir("/proc/self/task");
    if (!directory) return -1;
    int count = 0;
    while (auto entry = readdir(directory)) if (entry->d_name[0] != '.') ++count;
    closedir(directory);
    return count;
}
static Context *owned_context = nullptr;
static Context *owned_messageformat_context = nullptr;
static std::string messageformat_result, messageformat_error;
static bool platform_initialized = false;
static std::string last_error;
static pid_t owning_pid = 0;
static bool wait_owned(Context *c, bool boot) {
    std::unique_lock<std::mutex> guard(c->lock);
    bool ready = c->wake.wait_for(guard, std::chrono::seconds(c->messageformat ? 10 : 15), [&] { return c->done || (boot ? c->ready : c->replied); });
    if (!ready) {
        c->timed_out = true;
        if (c->state) v8_terminate_watchdog(c->state);
    }
    return ready && c->error.empty() && !c->done;
}
extern "C" const char *owned_layout_vm_error() { return last_error.c_str(); }
extern "C" void *owned_layout_vm_open(const char *source, int mode) {
    if (owned_context || platform_initialized || !source || (mode != 0 && mode != 1)) { last_error = "unadmitted overlapping/reopened native VM"; return nullptr; }
    auto c = new Context;
    c->source = source;
    if (c->source.empty() || c->source.size() > 32 * 1024 * 1024) { delete c; last_error = "unadmitted native VM source length"; return nullptr; }
    single_threaded = mode;
    v8_global_init();
    platform_initialized = true;
    owned_context = c;
    owning_pid = getpid();
    c->worker = std::thread([c] {
        auto state = v8_thread_init(c, nullptr, 0, 0, 0);
        if (single_threaded) {
            c->state = state;
            v8_single_threaded_enter(state, c, [](Context *value) { v8_thread_main(value, value->state); });
            v8_single_threaded_dispose(state);
        }
    });
    if (!wait_owned(c, true)) last_error = c->error.empty() ? "native VM boot timeout" : c->error;
    return c; // retained until explicit owned close, INCLUDING error paths
}
extern "C" const char *owned_layout_vm_version(void *handle) {
    auto c = static_cast<Context *>(handle);
    if (!c || c != owned_context || owning_pid != getpid() || !last_error.empty()) return "";
    {
        std::lock_guard<std::mutex> guard(c->lock);
        c->replied = false;
        c->call = true;
    }
    c->wake.notify_all();
    if (!wait_owned(c, false)) { last_error = c->error.empty() ? "native VM call timeout" : c->error; return ""; }
    return c->version.c_str();
}
extern "C" int owned_layout_vm_close(void *handle) {
    auto c = static_cast<Context *>(handle);
    if (!c || c != owned_context || owning_pid != getpid() || owned_messageformat_context) return -1;
    {
        std::lock_guard<std::mutex> guard(c->lock);
        c->stop = true;
    }
    c->wake.notify_all();
    c->worker.join();
    v8::V8::Dispose();
    v8::V8::DisposePlatform();
    delete platform;
    fprintf(stdout, "FIDELITY_NATIVE_VM_CLEANUP disposed=1 joined=1 callbacks=%zu calls=%zu\n", c->callbacks, c->calls);
    delete c;
    owned_context = nullptr;
    return 0;
}
extern "C" int owned_layout_vm_start(const char *source, int mode) {
    auto handle = owned_layout_vm_open(source, mode);
    return handle && last_error.empty() ? 0 : -1;
}
extern "C" const char *owned_layout_vm_read_version() { return owned_layout_vm_version(owned_context); }
extern "C" int owned_layout_vm_shutdown() { return owned_context ? owned_layout_vm_close(owned_context) : 0; }
// Exactly MessageFormat::Compiler#init_context/#compile, on its OWN original
// MiniRacer State/isolate. The existing application V8 platform remains alive.
// No arbitrary function/eval/endpoint API is exposed to the application caller.
extern "C" const char *owned_messageformat_error() { return messageformat_error.c_str(); }
extern "C" const char *owned_messageformat_compile(const char *sources, const char *locales, const char *messages, int strict) {
    messageformat_result.clear();
    messageformat_error.clear();
    if (!owned_context || !platform_initialized || owning_pid != getpid() || owned_messageformat_context ||
        !sources || !locales || !messages || (strict != 0 && strict != 1)) {
        messageformat_error = "unadmitted MessageFormat owner/platform/profile"; return "";
    }
    auto c = new Context;
    c->messageformat = true;
    c->strict = strict;
    c->source = sources;
    c->locales_json = locales;
    c->messages_json = messages;
    if (c->source.empty() || c->source.size() > 32 * 1024 * 1024 || c->locales_json.size() > 65536 || c->messages_json.size() > 16 * 1024 * 1024) {
        delete c; messageformat_error = "unbounded MessageFormat source/data"; return "";
    }
    owned_messageformat_context = c;
    c->worker = std::thread([c] {
        auto state = v8_thread_init(c, nullptr, 0, 0, 0);
        if (single_threaded) {
            c->state = state;
            v8_single_threaded_enter(state, c, [](Context *value) { v8_thread_main(value, value->state); });
            v8_single_threaded_dispose(state);
        }
    });
    bool ok = wait_owned(c, true);
    if (ok) {
        {
            std::lock_guard<std::mutex> guard(c->lock);
            c->call = true;
            c->replied = false;
        }
        c->wake.notify_all();
        ok = wait_owned(c, false);
    }
    if (ok) messageformat_result = c->version;
    else messageformat_error = c->error.empty() ? "owned MessageFormat timeout" : c->error;
    {
        std::lock_guard<std::mutex> guard(c->lock);
        c->stop = true;
    }
    c->wake.notify_all();
    c->worker.join();
    fprintf(stdout, "FIDELITY_NATIVE_MF_CLEANUP disposed=1 joined=1 calls=%zu timed_out=%d\n", c->calls, c->timed_out ? 1 : 0);
    delete c;
    owned_messageformat_context = nullptr;
    return messageformat_result.c_str();
}
#ifndef FIDELITY_V8_LIBRARY
int main(int argc, char **argv) {
    if (argc != 2) return 2;
    const char *root = getenv("FIDELITY_OWNED_VM_FIXTURE");
    std::string path = argv[1];
    struct stat info;
    if (!root || path != std::string(root) + "/asset-processor.js" || lstat(path.c_str(), &info) || !S_ISREG(info.st_mode) || info.st_uid != getuid() || info.st_nlink != 1) return 3;
    std::ifstream file(path, std::ios::binary);
    std::string source{std::istreambuf_iterator<char>(file), std::istreambuf_iterator<char>()};
    if (!file || source.empty() || source.size() > 32 * 1024 * 1024) return 4;
    const char *mode = getenv("FIDELITY_VM_SINGLE_THREADED");
    if (!mode || (strcmp(mode, "0") && strcmp(mode, "1"))) return 7;
    int threads_before = own_thread_count();
    auto context = owned_layout_vm_open(source.c_str(), !strcmp(mode, "1"));
    if (!context) return 8;
    std::string version = owned_layout_vm_version(context);
    std::string again = owned_layout_vm_version(context);
    bool ok = !version.empty() && version == again && last_error.empty();
    owned_layout_vm_close(context);
    int threads_after = own_thread_count();
    printf("FIDELITY_NATIVE_VM_THREADS threads_before=%d threads_after=%d\n", threads_before, threads_after);
    if (threads_before < 0 || threads_after != threads_before) return 6;
    if (!ok) { fprintf(stderr, "native owned VM refused: %s\n", last_error.c_str()); return 5; }
    printf("FIDELITY_NATIVE_VM_VERSION %s\n", version.c_str());
    return 0;
}
#endif
