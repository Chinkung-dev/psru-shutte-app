"""Build the PSRU map shuttle. Blender 5.x, no external assets required.

Run: blender --background --factory-startup --python tools/3d-shuttle/build_model.py
Dimensions are an approximation from the supplied front/side reference photo.
Blender: +Y front, +Z up. Exported glTF: -Z front, +Y up. Origin: ground centre.
"""
import bpy
import math
import json
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets' / 'models'
SOURCE = ROOT / 'tools' / '3d-shuttle'
OUT.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)


def material(name, rgb, metallic=0, roughness=.5):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*rgb, 1)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = (*rgb, 1)
    bsdf.inputs['Metallic'].default_value = metallic
    bsdf.inputs['Roughness'].default_value = roughness
    return mat


white = material('Ivory body and roof', (.88, .91, .88), .08, .34)
green = material('PSRU green', (.018, .24, .067), .05, .4)
glass = material('Dark teal windshield', (.025, .075, .085), .35, .18)
rubber = material('Tyres and wipers', (.012, .016, .018), 0, .85)
seat = material('Black upholstery', (.035, .045, .043), 0, .67)
metal = material('Brushed silver', (.46, .52, .52), .65, .3)
lamp = material('Headlight lenses', (.79, .89, .9), .4, .16)
red = material('Rear lights', (.65, .015, .012), .1, .25)
parts = []


def finish(obj, name, mat):
    obj.name = name
    obj.data.materials.append(mat)
    parts.append(obj)
    return obj


def box(name, loc, dims, mat, bevel=.025):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    obj = bpy.context.object
    obj.dimensions = dims
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        mod = obj.modifiers.new('Soft moulded edges', 'BEVEL')
        mod.width = bevel
        mod.segments = 2
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return finish(obj, name, mat)


def tube(name, a, b, radius, mat, vertices=10):
    a, b = Vector(a), Vector(b)
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius,
                                      depth=(b-a).length, location=(a+b)/2)
    obj = bpy.context.object
    obj.rotation_euler = (b-a).to_track_quat('Z', 'Y').to_euler()
    for poly in obj.data.polygons:
        poly.use_smooth = len(poly.vertices) == 4
    return finish(obj, name, mat)


def label(name, text, loc, rotation, size):
    bpy.ops.object.text_add(location=loc, rotation=rotation)
    obj = bpy.context.object
    obj.data.body = text
    obj.data.align_x = 'CENTER'
    obj.data.size = size
    obj.data.extrude = .001
    obj.data.resolution_u = 2
    bpy.ops.object.convert(target='MESH')
    return finish(bpy.context.object, name, green)


# Floor, lower side panels, and compact rounded nose.
box('Chassis', (0, 0, .49), (1.53, 4.9, .18), rubber, .06)
box('Passenger floor', (0, -.05, .68), (1.7, 4.6, .17), metal, .035)
box('Rounded front bonnet', (0, 2.03, .96), (1.78, .97, .91), white, .19)
for side in (-1, 1):
    box('Low open-side panel', (side*.845, -.38, .95), (.09, 3.84, .47), white, .035)
    box('Green sill stripe', (side*.897, -.38, .8), (.012, 3.73, .105), green, .006)
    box('Boarding step', (side*.94, .65, .46), (.28, .67, .09), metal, .025)
    label('Side PSRU branding', 'PSRU', (side*.906, -.55, .99),
          (math.pi/2, 0, side*math.pi/2), .245)
box('Rear panel', (0, -2.26, .94), (1.72, .16, .47), white, .065)
box('Rear bumper', (0, -2.4, .6), (1.78, .16, .13), metal, .04)
label('Front PSRU branding', 'PSRU', (0, 2.521, .96), (math.pi/2, 0, math.pi), .25)
label('Rear PSRU branding', 'PSRU', (0, -2.349, .93), (math.pi/2, 0, 0), .22)

# A curved, raked windshield surface (opaque tint keeps mobile sorting stable).
verts = []
for z, y, half_width in [(1.34, 2.49, .77), (1.65, 2.36, .79),
                          (2.1, 2.12, .76), (2.46, 1.88, .66)]:
    for i in range(9):
        t = (i-4)/4
        verts.append((t*half_width, y-.17*t*t, z))
faces = []
for row in range(3):
    for col in range(8):
        a = row*9+col
        faces.append((a, a+1, a+10, a+9))
mesh = bpy.data.meshes.new('Curved windshield geometry')
mesh.from_pydata(verts, [], faces)
mesh.update()
obj = bpy.data.objects.new('Panoramic windshield', mesh)
bpy.context.collection.objects.link(obj)
finish(obj, 'Panoramic windshield', glass)
for poly in mesh.polygons:
    poly.use_smooth = True
for side in (-1, 1):
    points = [(side*.81, 2.32, 1.27), (side*.83, 2.2, 1.65),
              (side*.80, 1.96, 2.12), (side*.7, 1.71, 2.46)]
    for a, b in zip(points, points[1:]):
        tube('White windscreen frame', a, b, .066, white)
    tube('Mirror arm', (side*.8, 1.94, 1.91), (side*1.07, 2.0, 1.91), .025, metal)
    box('Black side mirror', (side*1.08, 2, 1.91), (.14, .17, .34), rubber, .05)
    for z in (.77, 1.12):
        tube('Headlight bezel', (side*.65, 2.475, z), (side*.65, 2.515, z), .092, metal, 16)
        tube('Round headlight', (side*.65, 2.516, z), (side*.65, 2.526, z), .066, lamp, 16)
    box('Red tail light', (side*.68, -2.353, .99), (.16, .035, .21), red, .025)
    for y in (1.38, -1.63):
        tube('Tyre', (side*.76, y, .42), (side*1.0, y, .42), .42, rubber, 24)
        tube('Wheel rim', (side*1.001, y, .42), (side*1.013, y, .42), .29, metal, 20)
        tube('Hub', (side*1.014, y, .42), (side*1.04, y, .42), .09, rubber, 12)
        for i in range(8):
            angle = i*math.tau/8
            tube('Silver spoke', (side*1.025, y+.09*math.cos(angle), .42+.09*math.sin(angle)),
                 (side*1.025, y+.26*math.cos(angle), .42+.26*math.sin(angle)), .017, lamp, 6)

# Rows of seats, roof columns and passenger rails. The sides stay open.
for y in (1.12, .18, -.76, -1.7):
    box('Black bench cushion', (0, y, 1.04), (1.38, .48, .14), seat, .065)
    back = box('Black bench back', (0, y-.22, 1.37), (1.38, .14, .58), seat, .07)
    back.rotation_euler.x = -.10
    for side in (-1, 1):
        tube('Seat leg', (side*.51, y, .77), (side*.51, y, .98), .033, metal)
        tube('Roof pillar', (side*.8, y-.34, 1.14), (side*.8, y-.34, 2.47), .032, metal)
        tube('Passenger handrail', (side*.85, y+.19, 1.14), (side*.85, y+.19, 1.48), .021, metal)
        tube('Passenger handrail', (side*.85, y+.19, 1.48), (side*.85, y-.26, 1.56), .021, metal)
box('Long rounded canopy', (0, -.19, 2.49), (1.95, 4.75, .16), white, .075)
for side in (-1, 1):
    box('Canopy green trim', (side*.971, -.19, 2.465), (.015, 4.51, .035), green, .006)
for y in (-1.85, -.8, .3, 1.35):
    tube('Roof cross beam', (-.83, y, 2.38), (.83, y, 2.38), .025, metal)
tube('Wiper', (-.1, 2.515, 1.4), (.55, 2.22, 1.98), .014, rubber, 8)
tube('Wiper blade', (.40, 2.315, 1.82), (.65, 2.12, 2.11), .02, rubber, 8)
tube('Steering column', (-.43, 1.45, .85), (-.43, 1.74, 1.4), .035, rubber)
bpy.ops.mesh.primitive_torus_add(major_segments=20, minor_segments=6,
    location=(-.43, 1.74, 1.42), major_radius=.19, minor_radius=.018,
    rotation=(.55, 0, 0))
finish(bpy.context.object, 'Steering wheel', rubber)

# Merge by material: clones in Flutter share only eight small geometry buffers.
merged = []
by_material = {mat: [p for p in parts if p.data.materials[0] == mat]
               for mat in (white, green, glass, rubber, seat, metal, lamp, red)}
for mat in (white, green, glass, rubber, seat, metal, lamp, red):
    bpy.ops.object.select_all(action='DESELECT')
    selected = by_material[mat]
    for p in selected:
        p.select_set(True)
    bpy.context.view_layer.objects.active = selected[0]
    bpy.ops.object.join()
    obj = bpy.context.object
    obj.name = mat.name
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    merged.append(obj)

bpy.ops.object.select_all(action='DESELECT')
for obj in merged:
    obj.select_set(True)
bpy.ops.export_scene.gltf(filepath=str(OUT/'psru_shuttle.glb'), export_format='GLB',
    use_selection=True, export_yup=True, export_animations=False, export_cameras=False,
    export_lights=False, export_materials='EXPORT')
triangles = 0
for obj in merged:
    obj.data.calc_loop_triangles()
    triangles += len(obj.data.loop_triangles)
stats = {'triangles': triangles, 'meshes': len(merged), 'materials': 8,
         'bytes': (OUT/'psru_shuttle.glb').stat().st_size,
         'gltf_forward': '-Z', 'gltf_up': '+Y', 'origin': 'ground centre',
         'dimensions': 'approximate; single photo reference', 'textures': 0}
(SOURCE/'model_stats.json').write_text(json.dumps(stats, indent=2)+'\n', encoding='utf-8')

# Save an editable scene and four reproducible orthographic inspection views.
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.samples = 24
scene.render.resolution_x = 960
scene.render.resolution_y = 720
scene.render.resolution_percentage = 100
scene.world.color = (.45, .45, .45)
floor = box('Preview floor (not exported)', (0, 0, -.085), (200, 200, .1),
            material('Studio floor', (.65, .69, .67)), 0)
for location, energy, size in [((3, 5, 8), 1400, 5), ((-4, 1, 5), 1000, 4), ((0, -5, 7), 1300, 3)]:
    bpy.ops.object.light_add(type='AREA', location=location)
    light = bpy.context.object
    light.data.energy = energy
    light.data.shape = 'DISK'
    light.data.size = size
    light.rotation_euler = (Vector((0, 0, 1))-light.location).to_track_quat('-Z', 'Y').to_euler()
bpy.ops.object.camera_add()
camera = bpy.context.object
camera.data.type = 'ORTHO'
camera.data.ortho_scale = 7.1
scene.camera = camera
views = {'front': (6, 8, 5), 'side': (8, 0, 3.5), 'rear': (-6, -8, 5), 'map': (5, 7, 11)}
for name, loc in views.items():
    camera.location = loc
    camera.rotation_euler = (Vector((0, 0, 1.1))-camera.location).to_track_quat('-Z', 'Y').to_euler()
    scene.render.filepath = str(SOURCE/f'preview_{name}.png')
    bpy.ops.render.render(write_still=True)
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/'psru_shuttle.blend'))
print('SHUTTLE_MODEL', json.dumps(stats))
