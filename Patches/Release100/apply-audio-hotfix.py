from pathlib import Path

path = Path('Sources/Blackstock/Services/MasterVideoService.swift')
text = path.read_text()

old = '''    var audioParameters: [AVAudioMixInputParameters] = []
    if let originalAudio {
      let p = AVMutableAudioMixInputParameters(track: originalAudio)
      let profile = AudioMixProfileService.shared.profile(hasVoiceover: optionen.voiceover != nil, format: optionen.format)
      p.setVolume(profile.originalVolume, at: .zero)
      audioParameters.append(p)
    }
'''
new = '''    let audioProfile = AudioMixProfileService.shared.profile(
      hasVoiceover: optionen.voiceover != nil, format: optionen.format)
    var audioParameters: [AVAudioMixInputParameters] = []
    if let originalAudio {
      let p = AVMutableAudioMixInputParameters(track: originalAudio)
      p.setVolume(audioProfile.originalVolume, at: .zero)
      audioParameters.append(p)
    }
'''
if old not in text:
    raise SystemExit('Blackstock 100 audio profile anchor not found')
text = text.replace(old, new, 1)

old_voice = '        p.setVolume(1.0, at: .zero)\n        mixParameters.append(p)\n'
if old_voice not in text:
    raise SystemExit('Blackstock 100 voice mix anchor not found')
text = text.replace(old_voice, '        p.setVolume(audioProfile.voiceVolume, at: .zero)\n        mixParameters.append(p)\n', 1)

old_music = '        p.setVolume(0.10, at: .zero)\n        mixParameters.append(p)\n'
if old_music not in text:
    raise SystemExit('Blackstock 100 music mix anchor not found')
text = text.replace(old_music, '        p.setVolume(audioProfile.musicVolume, at: .zero)\n        mixParameters.append(p)\n', 1)

path.write_text(text)
print('BLACKSTOCK_100_AUDIO_HOTFIX_APPLIED')
