#include "windows_audio_route.h"

#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>

#include <windows.h>
#include <mmdeviceapi.h>
#include <wrl/client.h>

// The Windows audio control panel uses this COM interface to change the
// default output. The first ten method slots precede SetDefaultEndpoint.
// Keep external linkage so the compiler can dispatch to the Windows implementation.
struct AudioPolicyConfig : IUnknown {
    virtual HRESULT STDMETHODCALLTYPE GetMixFormat(PCWSTR, void**) = 0;
    virtual HRESULT STDMETHODCALLTYPE GetDeviceFormat(PCWSTR, INT, void**) = 0;
    virtual HRESULT STDMETHODCALLTYPE ResetDeviceFormat(PCWSTR) = 0;
    virtual HRESULT STDMETHODCALLTYPE SetDeviceFormat(PCWSTR, void*, void*) = 0;
    virtual HRESULT STDMETHODCALLTYPE GetProcessingPeriod(PCWSTR, INT, void*, void*) = 0;
    virtual HRESULT STDMETHODCALLTYPE SetProcessingPeriod(PCWSTR, void*) = 0;
    virtual HRESULT STDMETHODCALLTYPE GetShareMode(PCWSTR, void*) = 0;
    virtual HRESULT STDMETHODCALLTYPE SetShareMode(PCWSTR, void*) = 0;
    virtual HRESULT STDMETHODCALLTYPE GetPropertyValue(PCWSTR, const PROPERTYKEY&, PROPVARIANT*) = 0;
    virtual HRESULT STDMETHODCALLTYPE SetPropertyValue(PCWSTR, const PROPERTYKEY&, PROPVARIANT*) = 0;
    virtual HRESULT STDMETHODCALLTYPE SetDefaultEndpoint(PCWSTR, ERole) = 0;
};

namespace {
using Microsoft::WRL::ComPtr;
constexpr ERole mediaRoles[] = {eConsole, eMultimedia};

constexpr GUID policyClass{0x870af99c, 0x171d, 0x4f9e, {0xaf, 0x0d, 0xe6, 0x3d, 0xf4, 0x0c, 0x2b, 0xc9}};
constexpr GUID policyInterface{0xf8679f50, 0x850a, 0x41cf, {0x9c, 0x72, 0x43, 0x0f, 0x29, 0x02, 0x90, 0xc8}};

struct AudioPolicy {
    HRESULT com = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    ComPtr<IMMDeviceEnumerator> devices;
    ComPtr<AudioPolicyConfig> config;

    AudioPolicy() {
        if (FAILED(com) && com != RPC_E_CHANGED_MODE) return;
        CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
                         IID_PPV_ARGS(devices.GetAddressOf()));
        CoCreateInstance(policyClass, nullptr, CLSCTX_ALL, policyInterface,
                         reinterpret_cast<void**>(config.GetAddressOf()));
    }

    ~AudioPolicy() {
        config.Reset();
        devices.Reset();
        if (SUCCEEDED(com)) CoUninitialize();
    }

    QString defaultId(ERole role) const {
        ComPtr<IMMDevice> device;
        if (!devices || FAILED(devices->GetDefaultAudioEndpoint(eRender, role, device.GetAddressOf())))
            return {};
        PWSTR id = nullptr;
        if (FAILED(device->GetId(&id))) return {};
        const QString result = QString::fromWCharArray(id);
        CoTaskMemFree(id);
        return result;
    }

    bool setDefault(const QString& id, ERole role) const {
        return config && SUCCEEDED(config->SetDefaultEndpoint(
            reinterpret_cast<PCWSTR>(id.utf16()), role));
    }
};
}

WindowsAudioRoute::WindowsAudioRoute(const QString& recoveryPath)
    : m_recoveryPath(recoveryPath), m_lock(recoveryPath + QStringLiteral(".lock")) {
    m_lock.setStaleLockTime(0);
}

WindowsAudioRoute::Recovery WindowsAudioRoute::recover() {
    if (!QFile::exists(m_recoveryPath)) return Recovery::None;
    if (!m_lock.tryLock()) return Recovery::Unavailable;
    const bool restored = !QFile::exists(m_recoveryPath) || restore();
    m_lock.unlock();
    return restored ? Recovery::Restored : Recovery::Unavailable;
}

bool WindowsAudioRoute::start(const QString& source) {
    if (source.isEmpty() || !m_lock.tryLock()) return false;
    if (QFile::exists(m_recoveryPath) && !restore()) {
        m_lock.unlock();
        return false;
    }

    const AudioPolicy policy;
    QJsonArray previous;
    for (const ERole role : mediaRoles) {
        const QString id = policy.defaultId(role);
        if (id.isEmpty()) {
            m_lock.unlock();
            return false;
        }
        previous.append(id);
    }

    // Save the previous outputs before changing Windows so a later launch
    // can recover if this process is terminated while boost is running.
    QSaveFile file(m_recoveryPath);
    const QByteArray data = QJsonDocument(QJsonObject{
        {QStringLiteral("source"), source}, {QStringLiteral("previous"), previous}
    }).toJson(QJsonDocument::Compact);
    if (!file.open(QIODevice::WriteOnly) || file.write(data) != data.size() || !file.commit()) {
        m_lock.unlock();
        return false;
    }

    m_source = source;
    for (qsizetype i = 0; i < previous.size(); ++i) {
        const ERole role = mediaRoles[i];
        if ((previous.at(i).toString() != source && !policy.setDefault(source, role)) ||
            policy.defaultId(role) != source) {
            stop();
            return false;
        }
    }
    return true;
}

bool WindowsAudioRoute::stop() {
    if (!active()) return true;
    const bool restored = restore();
    m_source.clear();
    m_lock.unlock();
    return restored;
}

bool WindowsAudioRoute::restore() {
    QFile file(m_recoveryPath);
    if (!file.open(QIODevice::ReadOnly)) return false;
    const auto recovery = QJsonDocument::fromJson(file.readAll()).object();
    file.close();
    const QString source = recovery.value("source").toString();
    const QJsonArray previous = recovery.value("previous").toArray();
    if (source.isEmpty() || previous.size() != 2) return false;

    const AudioPolicy policy;
    bool restored = true;
    for (qsizetype i = 0; i < previous.size(); ++i) {
        const QString id = previous.at(i).toString();
        if (id == source) continue;
        const QString current = policy.defaultId(mediaRoles[i]);
        if (current.isEmpty()) restored = false;
        if (current != source) continue;
        if (id.isEmpty() || !policy.setDefault(id, mediaRoles[i])
                || policy.defaultId(mediaRoles[i]) != id) {
            restored = false;
        }
    }
    return restored && file.remove();
}
