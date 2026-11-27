#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <bcrypt.h>
#include <shellapi.h>
#include <tlhelp32.h>

#include <algorithm>
#include <array>
#include <cstdint>
#include <limits>
#include <memory>
#include <optional>
#include <string>
#include <string_view>
#include <utility>

namespace {

constexpr wchar_t appExecutable[] = L"super_booster.exe";
constexpr wchar_t uninstallKey[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\"
    L"{2FB21D94-87B2-432C-A6D9-6359C478234D}_is1";
constexpr DWORD readSharing = FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE;
constexpr DWORD appExitTimeoutMs = 90000;
constexpr std::size_t pathCapacity = 32768;

struct HandleCloser {
    void operator()(HANDLE handle) const { CloseHandle(handle); }
};
using Handle = std::unique_ptr<void, HandleCloser>;

Handle takeHandle(HANDLE handle) {
    return Handle(handle == INVALID_HANDLE_VALUE ? nullptr : handle);
}

bool pathEquals(std::wstring_view first, std::wstring_view second) {
    return CompareStringOrdinal(first.data(), static_cast<int>(first.size()),
                                second.data(), static_cast<int>(second.size()), TRUE) == CSTR_EQUAL;
}

std::wstring localPath(std::wstring path) {
    if (path.compare(0, 4, L"\\\\?\\") == 0) path.erase(0, 4);
    std::replace(path.begin(), path.end(), L'/', L'\\');
    if (path.size() < 3 || path[1] != L':' || path[2] != L'\\' ||
        !((path[0] >= L'A' && path[0] <= L'Z') || (path[0] >= L'a' && path[0] <= L'z')) ||
        path.find_first_of(L":\"*?<>|\r\n", 2) != std::wstring::npos) {
        return {};
    }

    std::wstring full(pathCapacity, L'\0');
    const DWORD length = GetFullPathNameW(path.c_str(), static_cast<DWORD>(full.size()),
                                         full.data(), nullptr);
    if (length == 0 || length >= full.size()) return {};
    full.resize(length);
    if (full.size() > 3 && full.back() == L'\\') full.pop_back();
    return full;
}

std::wstring longPath(const std::wstring& path) {
    return L"\\\\?\\" + path;
}

std::wstring directoryOf(const std::wstring& path) {
    const auto separator = path.find_last_of(L'\\');
    if (separator == std::wstring::npos) return {};
    return path.substr(0, separator == 2 ? 3 : separator);
}

std::wstring nameOf(const std::wstring& path) {
    return path.substr(path.find_last_of(L'\\') + 1);
}

std::wstring childPath(const std::wstring& dir, std::wstring_view name) {
    return dir + (dir.back() == L'\\' ? L"" : L"\\") + std::wstring(name);
}

std::wstring finalPath(HANDLE file) {
    std::wstring path(pathCapacity, L'\0');
    const DWORD length = GetFinalPathNameByHandleW(file, path.data(),
        static_cast<DWORD>(path.size()), FILE_NAME_NORMALIZED | VOLUME_NAME_DOS);
    if (length == 0 || length >= path.size()) return {};
    path.resize(length);
    return localPath(std::move(path));
}

Handle openPath(const std::wstring& path, DWORD access, DWORD sharing, bool directory) {
    if (path.empty()) return {};
    const DWORD flags = FILE_FLAG_OPEN_REPARSE_POINT |
        (directory ? FILE_FLAG_BACKUP_SEMANTICS : FILE_FLAG_SEQUENTIAL_SCAN);
    auto handle = takeHandle(CreateFileW(longPath(path).c_str(), access, sharing, nullptr,
                                        OPEN_EXISTING, flags, nullptr));
    BY_HANDLE_FILE_INFORMATION details{};
    if (!handle || !GetFileInformationByHandle(handle.get(), &details) ||
        (details.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) ||
        static_cast<bool>(details.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != directory) {
        return {};
    }
    return handle;
}

std::wstring registryString(const wchar_t* name) {
    std::wstring value(pathCapacity, L'\0');
    DWORD bytes = static_cast<DWORD>(value.size() * sizeof(wchar_t));
    if (RegGetValueW(HKEY_CURRENT_USER, uninstallKey, name, RRF_RT_REG_SZ, nullptr,
                     value.data(), &bytes) != ERROR_SUCCESS ||
        bytes < sizeof(wchar_t) || bytes % sizeof(wchar_t) != 0) {
        return {};
    }
    value.resize(bytes / sizeof(wchar_t) - 1);
    if (value.find(L'\0') != std::wstring::npos) return {};
    return value;
}

std::wstring processImage(HANDLE process) {
    std::wstring image(pathCapacity, L'\0');
    DWORD length = static_cast<DWORD>(image.size());
    if (!QueryFullProcessImageNameW(process, 0, image.data(), &length)) return {};
    image.resize(length);
    return localPath(std::move(image));
}

bool parseNumber(std::wstring_view text, std::uint64_t& value) {
    if (text.empty()) return false;
    value = 0;
    for (wchar_t character : text) {
        if (character < L'0' || character > L'9') return false;
        const auto digit = static_cast<std::uint64_t>(character - L'0');
        if (value > (std::numeric_limits<std::uint64_t>::max() - digit) / 10) return false;
        value = value * 10 + digit;
    }
    return true;
}

using Version = std::array<std::uint64_t, 3>;

bool parseVersion(std::wstring_view version, Version& components) {
    for (std::size_t index = 0; index < components.size(); ++index) {
        const bool last = index == components.size() - 1;
        const auto separator = version.find(L'.');
        if ((separator == std::wstring_view::npos) != last) return false;
        const auto segment = version.substr(0, separator);
        if ((segment.size() > 1 && segment.front() == L'0') ||
            !parseNumber(segment, components[index]) || components[index] > 65535) return false;
        if (!last) version.remove_prefix(separator + 1);
    }
    return true;
}

int hexDigit(wchar_t character) {
    if (character >= L'0' && character <= L'9') return character - L'0';
    if (character >= L'a' && character <= L'f') return character - L'a' + 10;
    return -1;
}

using Digest = std::array<UCHAR, 32>;

bool parseDigest(std::wstring_view text, Digest& digest) {
    if (text.size() != digest.size() * 2) return false;
    for (std::size_t index = 0; index < digest.size(); ++index) {
        const int high = hexDigit(text[2 * index]);
        const int low = hexDigit(text[2 * index + 1]);
        if (high < 0 || low < 0) return false;
        digest[index] = static_cast<UCHAR>((high << 4) | low);
    }
    return true;
}

bool candidateMatches(HANDLE file, std::uint64_t size, const Digest& expected) {
    LARGE_INTEGER actualSize{};
    if (!GetFileSizeEx(file, &actualSize) || actualSize.QuadPart <= 0 ||
        static_cast<std::uint64_t>(actualSize.QuadPart) != size) return false;

    BCRYPT_ALG_HANDLE algorithm = nullptr;
    if (BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_SHA256_ALGORITHM, nullptr, 0) < 0)
        return false;
    BCRYPT_HASH_HANDLE hash = nullptr;
    bool succeeded = BCryptCreateHash(algorithm, &hash, nullptr, 0, nullptr, 0, 0) >= 0;
    std::array<UCHAR, 65536> buffer{};
    std::uint64_t readTotal = 0;
    while (succeeded) {
        DWORD bytes = 0;
        succeeded = ReadFile(file, buffer.data(), static_cast<DWORD>(buffer.size()),
                             &bytes, nullptr) != FALSE;
        if (!succeeded || bytes == 0) break;
        readTotal += bytes;
        succeeded = BCryptHashData(hash, buffer.data(), bytes, 0) >= 0;
    }
    Digest actual{};
    const bool verified = succeeded && readTotal == size &&
        BCryptFinishHash(hash, actual.data(), static_cast<ULONG>(actual.size()), 0) >= 0 &&
        actual == expected;
    if (hash) BCryptDestroyHash(hash);
    BCryptCloseAlgorithmProvider(algorithm, 0);
    return verified;
}

bool writeMarker(const std::wstring& directory, const wchar_t* name, std::string_view message) {
    const auto target = longPath(childPath(directory, name));
    const auto temporary = target + L".partial";
    auto file = takeHandle(CreateFileW(temporary.c_str(), GENERIC_WRITE, 0, nullptr,
                                      CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr));
    if (!file) return false;
    DWORD written = 0;
    const bool saved = WriteFile(file.get(), message.data(), static_cast<DWORD>(message.size()),
                                 &written, nullptr) && written == message.size();
    file.reset();
    if (saved && MoveFileExW(temporary.c_str(), target.c_str(), MOVEFILE_WRITE_THROUGH))
        return true;
    DeleteFileW(temporary.c_str());
    return false;
}

Handle launch(const std::wstring& exe, const std::wstring& arguments, const std::wstring& cwd,
              bool hidden) {
    const auto image = exe.size() < MAX_PATH ? exe : longPath(exe);
    std::wstring commandLine = L"\"" + image + L"\"";
    if (!arguments.empty()) commandLine += L" " + arguments;
    STARTUPINFOW startup{};
    startup.cb = sizeof(startup);
    if (hidden) {
        startup.dwFlags = STARTF_USESHOWWINDOW;
        startup.wShowWindow = SW_HIDE;
    }
    PROCESS_INFORMATION child{};
    if (!CreateProcessW(image.c_str(), commandLine.data(), nullptr, nullptr, FALSE, 0, nullptr,
                        cwd.c_str(), &startup, &child)) {
        return {};
    }
    CloseHandle(child.hThread);
    return takeHandle(child.hProcess);
}

std::optional<bool> appStillRunning(const std::wstring& app) {
    auto snapshot = takeHandle(CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0));
    PROCESSENTRY32W entry{};
    entry.dwSize = sizeof(entry);
    if (!snapshot || !Process32FirstW(snapshot.get(), &entry)) return std::nullopt;
    do {
        if (!pathEquals(entry.szExeFile, appExecutable)) continue;
        auto process = takeHandle(OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE,
                                              entry.th32ProcessID));
        auto image = process ? openPath(processImage(process.get()), FILE_READ_ATTRIBUTES,
                                       readSharing, false) : Handle{};
        if (image && pathEquals(finalPath(image.get()), app)) return true;
    } while (Process32NextW(snapshot.get(), &entry));
    if (GetLastError() != ERROR_NO_MORE_FILES) return std::nullopt;
    return false;
}

struct Handoff {
    std::wstring scratch;
    std::wstring installedDirectory;
    std::wstring installedApp;
    std::wstring previousVersion;
    Handle scratchLock;
    bool ready = false;

    bool registeredDirectoryMatches() const {
        auto current = openPath(localPath(registryString(L"InstallLocation")),
                                FILE_READ_ATTRIBUTES, readSharing, true);
        return current && pathEquals(finalPath(current.get()), installedDirectory);
    }

    bool reopen() const {
        const auto running = appStillRunning(installedApp);
        if (!running) return false;
        if (*running) return true;
        auto app = openPath(installedApp, FILE_READ_ATTRIBUTES, readSharing, false);
        return app && registeredDirectoryMatches() &&
            pathEquals(finalPath(app.get()), installedApp) &&
            static_cast<bool>(launch(installedApp, {}, installedDirectory, false));
    }

    int fail(const char* message, const wchar_t* caption, bool recover = false) const {
        if (scratchLock) writeMarker(scratch, L"update-error.txt", message);
        if (ready) {
            if (recover && registryString(L"DisplayVersion") == previousVersion) reopen();
            MessageBoxW(nullptr, caption, L"Super Booster update", MB_OK | MB_ICONWARNING);
        }
        return 1;
    }
};

int performUpdate(wchar_t** arguments) {
    Handoff handoff;
    const auto installer = localPath(arguments[3]);
    if (installer.empty()) return 1;
    const auto scratch = directoryOf(installer);
    std::wstring helper(pathCapacity, L'\0');
    const DWORD helperLength = GetModuleFileNameW(nullptr, helper.data(), static_cast<DWORD>(helper.size()));
    if (helperLength == 0 || helperLength >= helper.size()) return 1;
    helper.resize(helperLength);
    auto helperFile = openPath(localPath(std::move(helper)), FILE_READ_ATTRIBUTES, readSharing, false);
    handoff.scratchLock = openPath(scratch, FILE_READ_ATTRIBUTES,
                                   FILE_SHARE_READ | FILE_SHARE_WRITE, true);
    if (!helperFile || !handoff.scratchLock) return 1;
    handoff.scratch = finalPath(handoff.scratchLock.get());
    if (handoff.scratch.empty() ||
        !pathEquals(directoryOf(finalPath(helperFile.get())), handoff.scratch)) {
        return 1;
    }

    const std::wstring version = arguments[6];
    constexpr char invalidMessage[] = "The staged Super Booster update could not be verified.";
    constexpr wchar_t invalidDetails[] = L"The update could not be verified. Download the update again.";
    std::uint64_t pid = 0;
    std::uint64_t size = 0;
    Digest expected{};
    Version targetVersion{};
    if (!parseNumber(arguments[1], pid) || pid == 0 || pid > std::numeric_limits<DWORD>::max() ||
        !parseNumber(arguments[5], size) || size == 0 || !parseDigest(arguments[4], expected) ||
        !parseVersion(version, targetVersion) ||
        nameOf(installer) != L"SuperBooster-" + version + L"-windows-x64-setup.exe") {
        return handoff.fail(invalidMessage, invalidDetails);
    }

    auto installFolder = openPath(localPath(arguments[2]), FILE_READ_ATTRIBUTES, readSharing, true);
    handoff.installedDirectory = installFolder ? finalPath(installFolder.get()) : std::wstring{};
    if (handoff.installedDirectory.empty() || !handoff.registeredDirectoryMatches() ||
        pathEquals(handoff.scratch, handoff.installedDirectory)) {
        return handoff.fail(invalidMessage, invalidDetails);
    }
    handoff.installedApp = childPath(handoff.installedDirectory, appExecutable);
    handoff.previousVersion = registryString(L"DisplayVersion");
    Version installedVersion{};
    auto parent = takeHandle(OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE, FALSE,
                                         static_cast<DWORD>(pid)));
    auto runningImage = parent ? openPath(processImage(parent.get()),
        FILE_READ_ATTRIBUTES, readSharing, false) : Handle{};
    if (!runningImage || !parseVersion(handoff.previousVersion, installedVersion) ||
        targetVersion <= installedVersion ||
        !pathEquals(finalPath(runningImage.get()), handoff.installedApp) ||
        WaitForSingleObject(parent.get(), 0) != WAIT_TIMEOUT) {
        return handoff.fail(invalidMessage, invalidDetails);
    }
    runningImage.reset();
    installFolder.reset();
    helperFile.reset();

    const auto candidate = childPath(handoff.scratch, nameOf(installer));
    auto verifiedFile = openPath(candidate, GENERIC_READ, FILE_SHARE_READ, false);
    if (!verifiedFile || !pathEquals(finalPath(verifiedFile.get()), candidate) ||
        !candidateMatches(verifiedFile.get(), size, expected)) {
        return handoff.fail(invalidMessage, invalidDetails);
    }
    std::wstring systemDir(pathCapacity, L'\0');
    const UINT systemLength = GetSystemDirectoryW(systemDir.data(), static_cast<UINT>(systemDir.size()));
    if (systemLength == 0 || systemLength >= systemDir.size())
        return handoff.fail(invalidMessage, invalidDetails);
    systemDir.resize(systemLength);

    if (!writeMarker(handoff.scratch, L"update-ready", "ready\n")) {
        return handoff.fail("The updater could not prepare the installation.",
                            L"The updater could not prepare the installation.");
    }
    handoff.ready = true;
    if (WaitForSingleObject(parent.get(), appExitTimeoutMs) != WAIT_OBJECT_0) {
        return handoff.fail("Super Booster did not finish closing.",
                            L"Super Booster did not finish closing. Close it and try again.");
    }
    const auto confirmPath = childPath(handoff.scratch, L"update-confirm");
    auto confirm = openPath(confirmPath, FILE_READ_ATTRIBUTES, FILE_SHARE_READ, false);
    if (!confirm || !pathEquals(finalPath(confirm.get()), confirmPath)) {
        writeMarker(handoff.scratch, L"update-error.txt", "The update was not confirmed.");
        return 1;
    }
    if (!handoff.registeredDirectoryMatches()) {
        return handoff.fail("The active Super Booster installation changed.",
                            L"The active installation changed. Reopen Super Booster and try again.");
    }
    const auto running = appStillRunning(handoff.installedApp);
    if (!running) {
        return handoff.fail("The updater could not check whether Super Booster was closed.",
                            L"The updater could not check whether Super Booster was closed. Try again.");
    }
    if (*running) {
        return handoff.fail("Another Super Booster window is still running.",
                            L"Close the other Super Booster window and try the update again.");
    }

    const auto setupLog = childPath(handoff.scratch, L"setup.log");
    if (GetFileAttributesW(longPath(setupLog).c_str()) != INVALID_FILE_ATTRIBUTES ||
        GetLastError() != ERROR_FILE_NOT_FOUND) {
        return handoff.fail("The updater could not create a new installation log.",
                            L"The updater could not prepare its installation log. Download the update again.",
                            true);
    }
    if (!pathEquals(finalPath(verifiedFile.get()), candidate)) {
        return handoff.fail("The verified installer location changed.",
                            L"The installer location changed. Download the update again.",
                            true);
    }
    const std::wstring flags = L"/SP- /VERYSILENT /SUPPRESSMSGBOXES /NORESTART "
        L"/RESTARTEXITCODE=3010 /NOCLOSEAPPLICATIONS /NORESTARTAPPLICATIONS /DIR=\"" +
        handoff.installedDirectory + L"\" /LOG=\"" + setupLog + L"\"";
    auto setup = launch(candidate, flags, systemDir, true);
    DWORD setupResult = 1;
    if (!setup || WaitForSingleObject(setup.get(), INFINITE) != WAIT_OBJECT_0 ||
        !GetExitCodeProcess(setup.get(), &setupResult)) {
        return handoff.fail("The Super Booster installer could not finish.",
                            L"The installer could not finish. Try again or run the installer manually.",
                            true);
    }
    verifiedFile.reset();
    if (setupResult == ERROR_SUCCESS_REBOOT_REQUIRED) {
        handoff.fail("Restart Windows to finish updating Super Booster.",
                     L"Restart Windows to finish updating Super Booster.");
        return ERROR_SUCCESS_REBOOT_REQUIRED;
    }
    if (setupResult != 0 || registryString(L"DisplayVersion") != version) {
        return handoff.fail("The Super Booster installer did not complete the update.",
                            L"The installer did not complete the update. Try again or run it manually.",
                            true);
    }
    if (!handoff.reopen()) {
        return handoff.fail("The update installed, but Super Booster could not be reopened.",
                            L"The update installed. Open Super Booster from the Start menu or its installation folder.");
    }
    return 0;
}

} // namespace

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
    int argc = 0;
    auto* argv = CommandLineToArgvW(GetCommandLineW(), &argc);
    const int result = argv && argc == 7 ? performUpdate(argv) : 1;
    if (argv) LocalFree(argv);
    return result;
}
