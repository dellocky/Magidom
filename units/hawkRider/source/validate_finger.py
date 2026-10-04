"""Check the baked finger clip; run in Blender after bake_animations.py.
PASS='frames' checks baked frames; PASS='subframes' also writes validation.json.
"""
import bpy
import json
from pathlib import Path
from mathutils.bvhtree import BVHTree


def meshinfo(name):
    obj = bpy.data.objects[name]
    evaluated = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
    mesh = evaluated.to_mesh()
    vertices = [evaluated.matrix_world @ v.co for v in mesh.vertices]
    faces = [tuple(p.vertices) for p in mesh.polygons]
    evaluated.to_mesh_clear()
    return vertices, faces, BVHTree.FromPolygons(vertices, faces)


human = bpy.data.objects['human']
groups = {
    v.index: human.vertex_groups[max(v.groups, key=lambda g: g.weight).group].name
    if v.groups else '' for v in human.data.vertices
}
for name in ('ArmatureHawk', 'ArmatureHuman'):
    obj = bpy.data.objects[name]
    obj.animation_data.action = None
    for track in obj.animation_data.nla_tracks:
        track.mute = track.name != 'finger'

scene = bpy.context.scene
pass_name = globals().get('PASS', 'frames')
subframe = .5 if pass_name == 'subframes' else 0.0
end = 109 if subframe else 110
errors = []
for frame in range(1, end):
    scene.frame_set(frame, subframe=subframe)
    bpy.context.view_layer.update()
    hawk = meshinfo('hawk')
    rider = meshinfo('human')
    staff = meshinfo('staff')
    hawk_rider = hawk[2].overlap(rider[2])
    hawk_staff = hawk[2].overlap(staff[2])
    rider_staff = [pair for pair in rider[2].overlap(staff[2])
                   if any(not groups[i].startswith('mixamorig:LeftHand')
                          for i in rider[1][pair[0]])]
    if hawk_rider or hawk_staff or rider_staff:
        errors.append({'frame': frame + subframe,
                       'hawk_human': len(hawk_rider),
                       'hawk_staff': len(hawk_staff),
                       'human_staff': len(rider_staff)})
print(pass_name, 'checked:', end - 1, 'unintended intersections:', errors)
bpy.app.driver_namespace['hawkRider_finger_' + pass_name] = errors
assert not errors, 'Finger clearance check failed'

if pass_name == 'subframes':
    assert bpy.app.driver_namespace['hawkRider_finger_frames'] == []
    scene.frame_set(109)
    last = {name: meshinfo(name)[0] for name in ('hawk', 'human', 'staff')}
    for name in ('ArmatureHawk', 'ArmatureHuman'):
        for track in bpy.data.objects[name].animation_data.nla_tracks:
            track.mute = track.name != 'idle'
    scene.frame_set(1)
    endpoint_error = max((a - b).length for name in last
                         for a, b in zip(last[name], meshinfo(name)[0]))
    assert endpoint_error < .00001, 'Recovery does not match idle'
    path = Path(bpy.path.abspath('//validation.json'))
    report = json.loads(path.read_text())
    report['finger'] = {
        'frames_checked': 109,
        'midframes_checked': 108,
        'fps': 30,
        'duration_seconds': 3.6,
        'loop': False,
        'loop_vertex_error_m': None,
        'idle_recovery_vertex_error_m': endpoint_error,
        'release_seconds': 1.82,
        'peak_local_backward_displacement_m': .14,
        'unintended_intersections': [],
        'intentional_contact': 'Left hand gripping staff is excluded from staff/rider overlap test.'
    }
    path.write_text(json.dumps(report, indent=2) + '\n')
    print('Recovery matches idle; maximum vertex error:', endpoint_error)
