"""Run in the original hawkRider Blender scene via Blender MCP.
Keeps the supplied meshes, seated pose, hand grip, and bone parenting.
"""
import bpy
import math
import json
from pathlib import Path
from mathutils import Matrix, Quaternion, Vector

if 'hawkRider_original' not in bpy.app.driver_namespace:
    data = json.loads(Path(bpy.path.abspath('//base_pose.json')).read_text())
    state = {name: {bone: Matrix(m) for bone, m in data[name].items()}
             for name in ('ArmatureHawk', 'ArmatureHuman')}
    state['posed'] = {name: {bone: Matrix(m) for bone, m in bones.items()}
                       for name, bones in data['posed'].items()}
    state['hand_matrix'] = Matrix(data['hand_matrix'])
    state['staff_axis'] = Vector(data['staff_axis'])
    bpy.app.driver_namespace['hawkRider_original'] = state
STATE = bpy.app.driver_namespace['hawkRider_original']
HAWK = bpy.data.objects['ArmatureHawk']
RIDER = bpy.data.objects['ArmatureHuman']
TAU = math.tau


def reset_pose():
    for obj in (HAWK, RIDER):
        for bone in obj.pose.bones:
            bone.matrix_basis = STATE[obj.name][bone.name]
    HAWK.location = (0, 0, 0)
    HAWK.rotation_mode = 'QUATERNION'
    HAWK.rotation_quaternion = (1, 0, 0, 0)
    bpy.context.view_layer.update()


def rotate(obj, name, axis, degrees):
    bone = obj.pose.bones[name]
    local_axis = STATE['posed'][obj.name][name].to_quaternion().inverted() @ Vector(axis)
    bone.rotation_quaternion = STATE[obj.name][name].to_quaternion() @ Quaternion(local_axis, math.radians(degrees))


def aim_bone(bone, target):
    bpy.context.view_layer.update()
    old = bone.matrix.copy()
    delta = (bone.tail - bone.head).normalized().rotation_difference((Vector(target) - bone.head).normalized())
    result = delta.to_matrix().to_4x4() @ old
    result.translation = old.translation
    bone.matrix = result
    bpy.context.view_layer.update()


def arm_pose(side, wrist, elbow_hint, hand_rotation):
    upper = RIDER.pose.bones['mixamorig:' + side + 'Arm']
    lower = RIDER.pose.bones['mixamorig:' + side + 'ForeArm']
    hand = RIDER.pose.bones['mixamorig:' + side + 'Hand']
    bpy.context.view_layer.update()
    shoulder = upper.head.copy()
    target = Vector(wrist)
    offset = target - shoulder
    distance = min(offset.length, upper.length + lower.length - .002)
    direction = offset.normalized()
    target = shoulder + direction * distance
    along = (upper.length**2 - lower.length**2 + distance**2) / (2 * distance)
    height = math.sqrt(max(0, upper.length**2 - along**2))
    pole = Vector(elbow_hint) - shoulder
    pole = (pole - direction * pole.dot(direction)).normalized()
    elbow = shoulder + direction * along + pole * height
    aim_bone(upper, elbow)
    aim_bone(lower, target)
    result = hand_rotation.to_matrix().to_4x4()
    result.translation = hand.head.copy()
    hand.matrix = result
    bpy.context.view_layer.update()


def smooth(t):
    t = max(0.0, min(1.0, t))
    return t*t*t*(t*(t*6.0 - 15.0) + 10.0)


def pose(clip, frame):
    reset_pose()
    t = (frame - 1) / 30.0
    period = .8 if clip == 'move' else 1.2
    phase = TAU * t / period
    # Wing-root motion stays small; the broader stroke starts outside the saddle.
    for side, root, shoulder, elbow, wrist, tip in [(1,6,7,8,9,10),(-1,11,12,13,14,15)]:
        rotate(HAWK, 'bone_' + str(root), (0,1,0), -side * (3 + 7*math.sin(phase)))
        rotate(HAWK, 'bone_' + str(shoulder), (0,1,0), -side * (-6 + 27*math.sin(phase)))
        rotate(HAWK, 'bone_' + str(elbow), (0,1,0), -side * (9*math.sin(phase-.42)))
        rotate(HAWK, 'bone_' + str(wrist), (0,1,0), -side * (6*math.sin(phase-.72)))
        rotate(HAWK, 'bone_' + str(tip), (0,1,0), -side * (3*math.sin(phase-.95)))
    pitch = 1.6 * math.sin(phase-.65) + (9 if clip == 'move' else 0)
    rotate(HAWK, 'tripo::Root', (1,0,0), pitch)
    rotate(HAWK, 'tripo::Spine_3', (1,0,0), -.55*pitch)
    rotate(HAWK, 'bone_27', (1,0,0), -2.8*math.sin(phase-.7))
    rotate(HAWK, 'tripo::Tail_0', (1,0,0), 2.1*math.sin(phase-1.15))
    for side in ('Left','Right'):
        rotate(HAWK, 'tripo::0_'+side+'_Limb_0', (1,0,0), -5 + 2*math.sin(phase-.8))
    HAWK.location.z = .045*math.sin(phase-1.0)
    # A delayed torso response absorbs the downstroke; hips stay planted.
    recoil = math.sin(phase-.95)
    rotate(RIDER, 'mixamorig:Spine', (1,0,0), -2.0*recoil - (4 if clip == 'move' else 0))
    rotate(RIDER, 'mixamorig:Spine1', (1,0,0), 1.1*math.sin(phase-1.2))
    rotate(RIDER, 'mixamorig:Head', (1,0,0), 1.0*recoil)
    bpy.context.view_layer.update()
    # Open the knees around the saddle rather than through its side panels.
    for side, sign in [('Left', 1), ('Right', -1)]:
        rotate(RIDER, 'mixamorig:'+side+'UpLeg', (0,0,1), sign*90)
    rotate(RIDER, 'mixamorig:RightArm', (1,0,0), -12)
    base_hand = STATE['hand_matrix'].to_quaternion()
    staff_axis = STATE['staff_axis']
    # Raised carry grip keeps the staff butt away from the ascending wing.
    carry_axis = Vector((.18,-.30,.94)).normalized()
    carry_rotation = staff_axis.rotation_difference(carry_axis) @ base_hand
    wrist = Vector((.278,-.073,1.355 + .006*math.sin(phase-1.1)))
    hand_rotation = carry_rotation
    if clip == 'finger':
        anticipation = smooth(t/.4) * (1-smooth((t-.4)/.55))
        charge = smooth((t-.4)/1.0) * (1-smooth((t-2.5)/1.1))
        # Fast release, delayed body reaction, then a small damped counter-kick.
        impact = smooth((t-1.82)/.085) * (1-smooth((t-1.905)/.60))
        rebound = .14*smooth((t-2.18)/.20) * (1-smooth((t-2.38)/.40))
        kick = impact - rebound
        head_kick = smooth((t-1.87)/.10) * (1-smooth((t-1.97)/.65))
        bird_kick = smooth((t-1.87)/.16) * (1-smooth((t-2.03)/.85))
        pushback = smooth((t-1.84)/.30) * (1-smooth((t-2.22)/1.13))
        HAWK.location.y = .14*pushback
        HAWK.location.z += .022*bird_kick
        rotate(HAWK, 'tripo::Root', (1,0,0), pitch - 7*bird_kick)
        rotate(HAWK, 'tripo::Spine_3', (1,0,0), -.55*pitch + 3*bird_kick)
        rotate(HAWK, 'bone_27', (1,0,0), -2.8*math.sin(phase-.7) + 5*bird_kick)
        rotate(RIDER, 'mixamorig:Spine', (1,0,0), -2*recoil + 6*anticipation - 8*charge - 19*kick)
        rotate(RIDER, 'mixamorig:Spine1', (1,0,0), 1.1*math.sin(phase-1.2) - 5*head_kick)
        rotate(RIDER, 'mixamorig:Spine2', (0,0,1), 5*charge - 3*kick)
        rotate(RIDER, 'mixamorig:Head', (1,0,0), -4*charge + (1-.4*charge)*recoil - 7*head_kick)
        wrist += Vector((.012,-.01,.018))*anticipation
        wrist = wrist.lerp(Vector((.25,-.21,1.34 + .003*recoil)), charge)
        cast_axis = Vector((0,-1,.09)).normalized()
        cast_rotation = Quaternion(cast_axis, math.radians(45)) @ staff_axis.rotation_difference(cast_axis) @ base_hand
        hand_rotation = carry_rotation.slerp(cast_rotation, charge)
        shaft_now = hand_rotation @ base_hand.inverted() @ staff_axis
        clear_axis = (shaft_now + Vector((-.85,0,0))*math.sin(math.pi*charge)).normalized()
        hand_rotation = shaft_now.rotation_difference(clear_axis) @ hand_rotation
        # Sweep the long butt outside the knee on the way into the aim pose.
        wrist += Vector((.035,-.02,.035)) * math.sin(math.pi*charge)
        wrist += Vector((.035,.085,.065))*kick
        hand_rotation = Quaternion((1,0,0), math.radians(-24*kick)) @ hand_rotation
        rotate(RIDER, 'mixamorig:RightArm', (1,0,0), -12 - 8*charge - 8*head_kick)
        rotate(RIDER, 'mixamorig:RightForeArm', (1,0,0), -8*charge - 10*kick)
    elif clip == 'staff_twirl':
        orbit = TAU*t/4.8
        HAWK.location.x = .24*(math.cos(orbit)-1)
        HAWK.location.y = -.24*math.sin(orbit)
        HAWK.rotation_quaternion = Quaternion((0,0,1),-orbit) @ Quaternion((0,1,0),math.radians(10))
        rotate(RIDER, 'mixamorig:Spine', (1,0,0), -12 - 1.6*recoil)
        rotate(RIDER, 'mixamorig:Spine2', (0,1,0), -4)
        rotate(RIDER, 'mixamorig:LeftShoulder', (0,1,0), -30)
        wrist = Vector((.12,.006,1.60 + .004*recoil))
        # Turn the palm upward so the gripped shaft clears both hat and sleeve.
        spin = TAU*t/2.4
        shaft = Vector((1,0,.02)).normalized()
        overhead = Quaternion(shaft, math.pi) @ staff_axis.rotation_difference(shaft) @ base_hand
        hand_rotation = Quaternion((0,0,1),spin) @ overhead
    bpy.context.view_layer.update()
    arm_pose('Left', wrist, (.45,.055,1.37), hand_rotation)
    bpy.context.view_layer.update()


bpy.app.driver_namespace['hawkRider_pose'] = pose
pose('idle', 1)
print('Hawk rider pose helpers ready')
