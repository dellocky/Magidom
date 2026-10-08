"""Author in-place Martyr clips on the existing imported Mixamo rig.

Run in Blender after importing units/martyr/idle.glb with bone_heuristic='BLENDER'.
No mesh, rest-pose, skin-weight or material changes. bake() makes editable actions;
export(glb_path, blend_path) writes the runtime model and isolated source scene.
"""
import math
from pathlib import Path

import bpy
from mathutils import Matrix, Quaternion, Vector

FPS = 30
CLIPS = {'idle': 120, 'run': 24, 'slap': 59, 'sillyrun': 28}
PREFIX = 'mixamorig:'
TAU = math.tau
RIG = next(obj for obj in bpy.context.scene.objects if obj.type == 'ARMATURE'
           and PREFIX + 'Hips' in obj.pose.bones)
REST = {bone.name: bone.matrix_local.copy() for bone in RIG.data.bones}
REST_HEAD = {bone.name: bone.head_local.copy() for bone in RIG.data.bones}


def bone(name):
    return RIG.pose.bones[PREFIX + name]


def update():
    bpy.context.view_layer.update()


def smooth(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3.0 - 2.0 * t)


def reset_pose():
    for pb in RIG.pose.bones:
        pb.rotation_mode = 'QUATERNION'
        pb.matrix_basis = Matrix.Identity(4)
    update()


def rotate(name, x=0.0, y=0.0, z=0.0):
    """World-axis deltas expressed in each bone's original local basis."""
    pb = bone(name)
    basis = REST[pb.name].to_quaternion()
    q = Quaternion((0, 0, 1), math.radians(z)) @ \
        Quaternion((0, 1, 0), math.radians(y)) @ \
        Quaternion((1, 0, 0), math.radians(x))
    pb.rotation_quaternion = basis.inverted() @ q @ basis


def hip_offset(x, y, z):
    pb = bone('Hips')
    pb.location = REST[pb.name].to_3x3().inverted() @ Vector((x, y, z))


def aim(pb, point):
    update()
    matrix = pb.matrix.copy()
    delta = (pb.tail - pb.head).normalized().rotation_difference(
        (Vector(point) - pb.head).normalized())
    result = delta.to_matrix().to_4x4() @ matrix
    result.translation = matrix.translation
    pb.matrix = result
    update()


def limb(upper_name, lower_name, target, pole):
    upper, lower = bone(upper_name), bone(lower_name)
    update()
    origin = upper.head.copy()
    offset = Vector(target) - origin
    length_a = (REST_HEAD[lower.name] - REST_HEAD[upper.name]).length
    end_name = lower_name.replace('ForeArm', 'Hand') if 'ForeArm' in lower_name else lower_name.replace('Leg', 'Foot')
    length_b = (REST_HEAD[PREFIX + end_name] - REST_HEAD[lower.name]).length
    distance = max(0.001, min(offset.length, length_a + length_b - 0.002))
    direction = offset.normalized()
    along = (length_a ** 2 - length_b ** 2 + distance ** 2) / (2 * distance)
    height = math.sqrt(max(0.0, length_a ** 2 - along ** 2))
    perpendicular = Vector(pole) - origin
    perpendicular -= direction * perpendicular.dot(direction)
    perpendicular.normalize()
    elbow = origin + direction * along + perpendicular * height
    aim(upper, elbow)
    aim(lower, origin + direction * distance)


def orient_end(name, direction, roll=0.0):
    pb = bone(name)
    update()
    rest = REST[pb.name]
    q = rest.col[1].xyz.normalized().rotation_difference(Vector(direction).normalized()) @ rest.to_quaternion()
    q = Quaternion(Vector(direction).normalized(), math.radians(roll)) @ q
    matrix = q.to_matrix().to_4x4()
    matrix.translation = pb.head.copy()
    pb.matrix = matrix
    update()


def foot(side, target, pitch=0.0):
    sign = 1 if side == 'Left' else -1
    limb(side + 'UpLeg', side + 'Leg', target, (sign * 0.10, -0.45, 0.28))
    pb = bone(side + 'Foot')
    update()
    q = Quaternion((1, 0, 0), math.radians(pitch)) @ REST[pb.name].to_quaternion()
    matrix = q.to_matrix().to_4x4()
    matrix.translation = pb.head.copy()
    pb.matrix = matrix
    rotate(side + 'ToeBase', x=-max(pitch, 0.0) * 0.65)
    update()


def arm(side, wrist, pole, hand_direction=(0, -0.15, -1), roll=0.0):
    limb(side + 'Arm', side + 'ForeArm', wrist, pole)
    orient_end(side + 'Hand', hand_direction, roll)


def planted_feet():
    for side in ('Left', 'Right'):
        foot(side, REST_HEAD[PREFIX + side + 'Foot'])


def idle(t):
    phase = TAU * t / 4.0
    breath = math.sin(phase)
    sway = math.sin(phase + 0.55)
    hip_offset(0.007 * sway, 0.0, -0.019 + 0.003 * breath)
    rotate('Hips', y=1.1 * sway, z=1.5 * math.sin(phase - 0.4))
    rotate('Spine', x=1.1 * breath, y=-1.4 * sway)
    rotate('Spine1', x=1.4 * math.sin(phase - 0.20))
    rotate('Spine2', x=-0.7 * math.sin(phase - 0.4), z=-1.0 * math.sin(phase - 0.6))
    glance = smooth((t - 0.75) / 0.65) * (1 - smooth((t - 2.3) / 0.9))
    rotate('Neck', x=0.8 * math.sin(phase - 0.5), z=-3 * glance)
    rotate('Head', x=-1.2 * math.sin(phase - 0.35), y=1.0 * math.sin(phase - 0.75), z=-8 * glance)
    for side, sign in (('Left', 1), ('Right', -1)):
        rotate(side + 'Shoulder', x=0.7 * breath, y=-sign * 1.2 * breath)
        wrist = (sign * (0.164 + 0.003 * math.sin(phase - 0.8)),
                 -0.015 + 0.006 * math.sin(phase - 0.6 + sign * 0.25),
                 0.570 + 0.004 * math.sin(phase - 0.35))
        arm(side, wrist, (sign * 0.26, 0.08, 0.67),
            (sign * 0.08, -0.18 + 0.07 * math.sin(phase - 1.0), -1),
            sign * (4 + 2 * math.sin(phase - 0.9)))
    planted_feet()


def running(t, silly=False):
    period = CLIPS['sillyrun' if silly else 'run'] / FPS
    phase = TAU * t / period
    hip_offset(0.009 * math.sin(phase), 0.0,
               -0.048 + (0.022 if silly else 0.019) * math.cos(2 * phase - 0.8))
    rotate('Hips', x=4 if silly else 6, y=2.5 * math.sin(phase), z=5 * math.sin(phase))
    if silly:
        rotate('Spine', x=-8 - 3 * math.sin(phase - 0.45), y=3 * math.sin(phase - 0.4), z=-4 * math.sin(phase - 0.35))
        rotate('Spine1', x=-9 - 4 * math.sin(phase - 0.85), y=3 * math.sin(phase - 0.8))
        rotate('Spine2', x=-7 - 4 * math.sin(phase - 1.2), z=-3 * math.sin(phase - 0.9))
        rotate('Neck', x=5 + 4 * math.sin(phase - 1.35), y=3 * math.sin(phase - 1.4))
        rotate('Head', x=5 + 5 * math.sin(phase - 1.6), y=4 * math.sin(phase - 1.65))
    else:
        rotate('Spine', x=3, z=-6 * math.sin(phase - 0.20))
        rotate('Spine1', x=1.5 * math.sin(2 * phase - 0.3), y=-1.5 * math.sin(phase))
        rotate('Spine2', z=-3 * math.sin(phase - 0.3))
        rotate('Neck', x=-3)
        rotate('Head', x=-5 - 1.3 * math.sin(2 * phase - 0.4), z=3 * math.sin(phase - 0.2))
    update()
    for side, sign, shift in (('Left', 1, 0.0), ('Right', -1, 0.5)):
        u = (t / period + shift) % 1.0
        stride = 0.34 if silly else 0.32
        if u < 0.5:
            v = u / 0.5
            y = stride * (v - 0.5)
            lift = 0.0
            pitch = -6 * (1 - smooth(v / 0.25)) + 17 * smooth((v - 0.65) / 0.35)
        else:
            v = (u - 0.5) / 0.5
            y = stride * (0.5 - smooth(v))
            lift = (0.14 if silly else 0.10) * math.sin(math.pi * v) ** 1.2
            pitch = 17 * (1 - smooth(v / 0.3)) + 22 * math.sin(math.pi * v) - 6 * smooth((v - 0.65) / 0.35)
        foot(side, (sign * (0.09 if silly else 0.083), y + 0.0137, 0.0566 + lift), pitch)
        local_phase = phase + shift * TAU
        if silly:
            head = bone('Head').head.copy()
            wrist = head + Vector((sign * (0.135 + 0.012 * math.sin(local_phase - 0.7)),
                                   0.015 + 0.016 * math.sin(local_phase - 1.0),
                                   0.166 + 0.012 * math.sin(local_phase - 0.9)))
            arm(side, wrist, head + Vector((sign * 0.30, 0.06, 0.06)),
                (sign * 0.22, 0.28 * math.sin(local_phase - 1.6), 1),
                sign * (12 + 16 * math.sin(local_phase - 1.4)))
        else:
            swing = math.cos(local_phase)
            arm(side, (sign * 0.15, -0.07 + 0.13 * swing, 0.66 - 0.055 * swing),
                (sign * 0.18, 0.09 + 0.05 * swing, 0.47),
                (sign * 0.05, -0.7, 0.5), sign * 8)


def interpolate_keys(t, keys):
    for (ta, va), (tb, vb) in zip(keys, keys[1:]):
        if t <= tb:
            return Vector(va).lerp(Vector(vb), smooth((t - ta) / (tb - ta)))
    return Vector(keys[-1][1])


def slap(t):
    # Endpoints exactly match the idle's first pose, including its slight sway.
    idle(0.0)
    baseline = {pb.name: (pb.location.copy(), pb.rotation_quaternion.copy()) for pb in RIG.pose.bones}
    if t <= 0.0 or t >= 59 / FPS:
        return
    windup = smooth(t / 0.26) * (1 - smooth((t - 0.26) / 0.14))
    hit = smooth((t - 0.26) / 0.14) * (1 - smooth((t - 0.53) / 0.55))
    recovery = smooth((t - 0.95) / (59 / FPS - 0.95))
    envelope = 1 - recovery
    rotate('Hips', z=1.5 * math.sin(-0.4) + 9 * windup - 10 * hit)
    hip_offset(0.007 * math.sin(0.55) - 0.009 * windup + 0.016 * hit, -0.012 * hit, -0.019 - 0.012 * windup)
    rotate('Spine', x=-4 * windup + 8 * hit, y=-1.4 * math.sin(0.55), z=12 * windup - 14 * hit)
    rotate('Spine1', x=1.4 * math.sin(-0.2) - 3 * windup + 3 * hit)
    rotate('Spine2', x=-0.7 * math.sin(-0.4), z=-math.sin(-0.6) + 12 * windup - 14 * hit)
    rotate('Head', x=-1.2 * math.sin(-0.35) - 3 * hit, y=math.sin(-0.75), z=-10 * windup + 11 * hit)
    update()
    base_right = bone('RightHand').head.copy()
    # Contact at 0.4 s is the existing whack damage event, followed by overshoot.
    wrist = interpolate_keys(t, [
        (0.0, base_right), (0.24, (-0.25, 0.035, 0.84)),
        (0.32, (-0.26, -0.06, 0.88)), (0.4, (-0.025, -0.29, 0.84)),
        (0.55, (0.19, -0.21, 0.76)), (0.9, (0.11, -0.14, 0.67)),
        (59 / FPS, (-0.164 - 0.003 * math.sin(-0.8), -0.015 + 0.006 * math.sin(-0.85), 0.570 + 0.004 * math.sin(-0.35)))])
    activity = smooth(t / 0.16) * envelope
    hand_dir = Vector((-0.08, -0.18 + 0.07 * math.sin(-1.0), -1)).lerp(
        Vector((0.8, -0.6, 0.15)), activity)
    arm('Right', wrist, (-0.33, 0.03, 0.72), hand_dir, -3 + 35 * activity)
    arm('Left', (0.164 + 0.035 * hit, -0.015 - 0.02 * windup, 0.570 + 0.05 * windup),
        (0.27, 0.075, 0.67), (0.08, -0.2, -1), 4)
    planted_feet()
    blend = smooth(t / 0.08) * (1 - smooth((t - 1.2) / (59 / FPS - 1.2)))
    for pb in RIG.pose.bones:
        location, rotation = baseline[pb.name]
        pb.location = location.lerp(pb.location, blend)
        pb.rotation_quaternion = rotation.slerp(pb.rotation_quaternion, blend)


def pose(clip, frame):
    reset_pose()
    t = (frame - 1) / FPS
    if clip == 'idle':
        idle(t)
    elif clip == 'slap':
        slap(t)
    else:
        running(t, silly=clip == 'sillyrun')
    update()


def bake():
    RIG.animation_data_create()
    RIG.animation_data.action = None
    for track in list(RIG.animation_data.nla_tracks):
        RIG.animation_data.nla_tracks.remove(track)
    for action in list(bpy.data.actions):
        if action.get('martyr_clip') in CLIPS:
            action.use_fake_user = False
            if action.users == 0:
                bpy.data.actions.remove(action)
    samples = {}
    for clip, frames in CLIPS.items():
        samples[clip] = []
        for frame in range(1, frames + 2):
            pose(clip, frame)
            samples[clip].append({pb.name: (pb.location.copy(), pb.rotation_quaternion.copy())
                                  for pb in RIG.pose.bones})
    for clip, values in samples.items():
        action = bpy.data.actions.new('Martyr_' + clip)
        action.use_fake_user = True
        action['martyr_clip'] = clip
        action.use_frame_range = True
        action.frame_start, action.frame_end = 1, CLIPS[clip] + 1
        RIG.animation_data.action = action
        previous = {}
        for frame, bones in enumerate(values, 1):
            for name, (location, rotation) in bones.items():
                pb = RIG.pose.bones[name]
                if name in previous:
                    rotation.make_compatible(previous[name])
                previous[name] = rotation.copy()
                pb.location, pb.rotation_quaternion = location, rotation
                pb.keyframe_insert('location', frame=frame, group=name)
                pb.keyframe_insert('rotation_quaternion', frame=frame, group=name)
        slot = RIG.animation_data.action_slot
        for layer in action.layers:
            for strip in layer.strips:
                bag = strip.channelbag(slot)
                if bag:
                    for curve in bag.fcurves:
                        for key in curve.keyframe_points:
                            key.interpolation = 'LINEAR'
        track = RIG.animation_data.nla_tracks.new()
        track.name = clip
        strip = track.strips.new(clip, 1, action)
        strip.action_slot = slot
        strip.extrapolation = 'NOTHING'
        strip.blend_type = 'REPLACE'
        track.mute = True
        RIG.animation_data.action = None
        print('Baked', clip, CLIPS[clip] + 1, 'keys')
    bpy.context.scene.render.fps = FPS
    preview('idle')


def preview(clip):
    RIG.animation_data.action = None
    for track in RIG.animation_data.nla_tracks:
        track.mute = track.name != clip
    scene = bpy.context.scene
    scene.frame_start, scene.frame_end = 1, CLIPS[clip] + 1
    scene.frame_set(1)
    update()


def export(glb_path, blend_path):
    scene = bpy.context.scene
    for obj in scene.objects:
        obj.select_set(False)
    RIG.select_set(True)
    for obj in RIG.children_recursive:
        if obj.type == 'MESH':
            obj.select_set(True)
    bpy.context.view_layer.objects.active = RIG
    RIG.animation_data.action = None
    for track in RIG.animation_data.nla_tracks:
        track.mute = False
    bpy.ops.export_scene.gltf(filepath=str(glb_path), export_format='GLB',
        use_selection=True, use_active_scene=True, export_animations=True, export_animation_mode='NLA_TRACKS',
        export_frame_range=False, export_force_sampling=True, export_anim_slide_to_zero=True,
        export_cameras=False, export_lights=False)
    preview('idle')
    # Write only this authoring scene and its dependencies, not the user's scene.
    bpy.data.libraries.write(str(blend_path), {scene}, fake_user=True)
    print('Exported', glb_path, 'and', blend_path)


bpy.app.driver_namespace['martyr_animator'] = globals()
if __name__ == '__main__':
    bake()
