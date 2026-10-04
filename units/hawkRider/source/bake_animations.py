"""Bake the analytic poses to paired NLA tracks for a single GLB animation per clip."""
import bpy
from mathutils import Quaternion

namespace = bpy.app.driver_namespace['hawkRider_animator']
pose = namespace['pose']
objects = [bpy.data.objects['ArmatureHawk'], bpy.data.objects['ArmatureHuman']]
clips = {'idle': 73, 'move': 49, 'finger': 109, 'staff_twirl': 145}
# Supply CLIPS_TO_BAKE in exec globals to replace just selected generated clips.
requested = globals().get('CLIPS_TO_BAKE', tuple(clips))
assert all(clip in clips for clip in requested), 'Unknown clip requested'
clips = {clip: end for clip, end in clips.items() if clip in requested}

for obj in objects:
    obj.animation_data_create()
    obj.animation_data.action = None
    for track in obj.animation_data.nla_tracks:
        track.mute = True

# Capture first; evaluating an action while generating poses would contaminate them.
samples = {}
for clip, end in clips.items():
    samples[clip] = []
    for frame in range(1, end + 1):
        pose(clip, frame)
        samples[clip].append({obj.name: {
            'location': obj.location.copy(),
            'rotation': obj.rotation_quaternion.copy(),
            'bones': {p.name: (p.location.copy(), p.rotation_quaternion.copy(), p.scale.copy())
                      for p in obj.pose.bones}
        } for obj in objects})

for clip, end in clips.items():
    for obj in objects:
        action_name = clip + '__' + ('hawk' if obj == objects[0] else 'rider')
        old_action = bpy.data.actions.get(action_name)
        if old_action:
            assert old_action.get('clip') == clip, 'Refusing to replace an unrecognized action'
        for old_track in list(obj.animation_data.nla_tracks):
            if old_track.name == clip:
                assert all(s.action == old_action for s in old_track.strips), 'Unexpected NLA content'
                obj.animation_data.nla_tracks.remove(old_track)
        if old_action:
            old_action.use_fake_user = False
            assert old_action.users == 0, 'Action is used outside its generated track'
            bpy.data.actions.remove(old_action)
        action = bpy.data.actions.new(action_name)
        action.use_fake_user = True
        action['clip'] = clip
        obj.animation_data.action = action
        previous = {}
        for frame, sample in enumerate(samples[clip], 1):
            data = sample[obj.name]
            obj.location = data['location']
            q = data['rotation'].copy()
            if 'object' in previous:
                q.make_compatible(previous['object'])
            previous['object'] = q.copy()
            obj.rotation_quaternion = q
            obj.keyframe_insert('location', frame=frame)
            obj.keyframe_insert('rotation_quaternion', frame=frame)
            for name, (location, rotation, scale) in data['bones'].items():
                bone = obj.pose.bones[name]
                q = rotation.copy()
                if name in previous:
                    q.make_compatible(previous[name])
                previous[name] = q.copy()
                bone.location = location
                bone.rotation_quaternion = q
                bone.scale = scale
                bone.keyframe_insert('location', frame=frame, group=name)
                bone.keyframe_insert('rotation_quaternion', frame=frame, group=name)
                bone.keyframe_insert('scale', frame=frame, group=name)
        slot = obj.animation_data.action_slot
        for layer in action.layers:
            for strip in layer.strips:
                bag = strip.channelbag(slot)
                if bag:
                    for curve in bag.fcurves:
                        for key in curve.keyframe_points:
                            key.interpolation = 'LINEAR'
        track = obj.animation_data.nla_tracks.new()
        track.name = clip
        strip = track.strips.new(clip, 1, action)
        strip.action_slot = slot
        strip.extrapolation = 'NOTHING'
        strip.blend_type = 'REPLACE'
        track.mute = True
        obj.animation_data.action = None
    print('Baked', clip, end, 'frames')

for obj in objects:
    for track in obj.animation_data.nla_tracks:
        track.mute = track.name != 'idle'
scene = bpy.context.scene
scene.render.fps = 30
scene.frame_start = 1
scene.frame_end = 73
scene.frame_set(1)
print('Baking complete:', ', '.join(clips), 'on two existing armatures.')
