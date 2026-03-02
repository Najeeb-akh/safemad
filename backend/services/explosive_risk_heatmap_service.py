# # #!/usr/bin/env python3
# # """
# # Explosive Risk Heatmap Service
# # Generates safety heatmaps for floor plans based on explosive attack risk assessment
# # """

# # import numpy as np
# # import math
# # from typing import Dict, List, Tuple, Any, Optional
# # from dataclasses import dataclass
# # from enum import Enum
# # from PIL import Image
# # from datetime import datetime

# # try:
# #     from scipy.spatial.distance import cdist
# #     from scipy.ndimage import gaussian_filter
# # except ImportError:
# #     # Fallback implementations if scipy is not available
# #     def gaussian_filter(matrix, sigma=1):
# #         return matrix
    
# #     def cdist(XA, XB):
# #         return np.array([[np.linalg.norm(np.array(a) - np.array(b)) for b in XB] for a in XA])

# # class RiskLevel(Enum):
# #     VERY_LOW = 1
# #     LOW = 2
# #     MEDIUM = 3
# #     HIGH = 4
# #     VERY_HIGH = 5

# # @dataclass
# # class GridPoint:
# #     x: int
# #     y: int
# #     safety_score: float
# #     risk_level: RiskLevel
# #     factors: Dict[str, float]
# #     evacuation_time: float
# #     blast_protection: float

# # @dataclass
# # class ExplosiveRiskFactors:
# #     """Factors that affect explosive attack risk and safety"""
    
# #     # Structural Protection
# #     wall_material_protection: float = 0.0
# #     wall_thickness_protection: float = 0.0
# #     ceiling_protection: float = 0.0
# #     floor_material: float = 0.0
    
# #     # Blast Wave Factors
# #     distance_from_exterior: float = 0.0
# #     distance_from_windows: float = 0.0
# #     distance_from_doors: float = 0.0
# #     corner_effect: float = 0.0
    
# #     # Evacuation Factors
# #     evacuation_route_distance: float = 0.0
# #     evacuation_route_obstacles: float = 0.0
# #     emergency_exit_access: float = 0.0
    
# #     # Environmental Factors
# #     room_size_factor: float = 0.0
# #     ventilation_factor: float = 0.0
# #     debris_risk: float = 0.0
    
# #     # Special Considerations
# #     mamad_protection: float = 0.0
# #     reinforced_area: float = 0.0
# #     critical_infrastructure: float = 0.0
# #     # New – Openings & additional protections
# #     opening_penalty: float = 0.0
# #     mamad_distance_bonus: float = 0.0
# #     roof_protection: float = 0.0

# # class ExplosiveRiskHeatmapService:
# #     def __init__(self):
# #         self.grid_resolution = 15  # Grid cell size in pixels (reduced for better coverage)
# #         self.blast_radius_meters = 50  # Effective blast radius in meters
# #         self.pixel_to_meter_ratio = 0.1  # Default: 10 pixels = 1 meter
        
# #         # Material protection factors (0-1, higher = better protection)
# #         self.material_protection_values = {
# #             'concrete': 0.85,
# #             'reinforced_concrete': 0.95,
# #             'brick': 0.70,
# #             'stone': 0.75,
# #             'wood': 0.30,
# #             'drywall': 0.20,
# #             'glass': 0.05,
# #             'metal': 0.60,
# #             'unknown': 0.40
# #         }
        
# #         # Wall thickness protection (cm to protection factor)
# #         self.thickness_protection_values = {
# #             'very_thick': 0.70,  # >30cm - reduced from 0.90
# #             'thick': 0.55,       # 20-30cm - reduced from 0.75
# #             'medium': 0.35,      # 10-20cm - reduced from 0.50
# #             'thin': 0.15,        # <10cm - reduced from 0.25
# #             'unknown': 0.25      # reduced from 0.40
# #         }

# #         # Glazing resistance factors (0-1, higher = better blast resistance)
# #         self.glazing_resistance = {
# #             'ordinary': 0.10,
# #             'single_glazed': 0.15,
# #             'double_glazed': 0.25,
# #             'laminated': 0.40,
# #             'blast': 0.70,
# #             'unknown': 0.10
# #         }

# #         # Debug flag – verbose stats printed when True
# #         self.debug = True

# #     async def generate_heatmap(self, floor_plan_data: dict, analysis_id: str = None) -> dict:
# #         """Generate explosive risk heatmap for floor plan"""
# #         try:
# #             print(f"[HEATMAP_DEBUG] Starting heatmap generation")
# #             print(f"[HEATMAP_DEBUG] analysis_id: {analysis_id}")
# #             print(f"[HEATMAP_DEBUG] floor_plan_data keys: {list(floor_plan_data.keys()) if floor_plan_data else 'None'}")
            
# #             # For compatibility mode, use the existing generate_explosive_risk_heatmap method
# #             if not analysis_id:
# #                 print(f"[HEATMAP_DEBUG] No analysis_id, using compatibility mode")
# #                 print(f"[HEATMAP_DEBUG] Using compatibility mode for heatmap generation")
# #                 try:
# #                     result = self.generate_explosive_risk_heatmap(floor_plan_data)
# #                     print(f"[HEATMAP_DEBUG] ✅ Compatibility mode heatmap generation completed")
# #                     return result
# #                 except Exception as e:
# #                     print(f"[HEATMAP_DEBUG] ERROR in compatibility mode: {e}")
# #                     import traceback
# #                     print(f"[HEATMAP_DEBUG] Full traceback: {traceback.format_exc()}")
# #                     raise
            
# #             # For structured mode with analysis_id, get structured data
# #             print(f"[HEATMAP_DEBUG] Using structured mode with analysis_id: {analysis_id}")
# #             try:
# #                 # This would call the structured safety service
# #                 # For now, fall back to compatibility mode
# #                 print(f"[HEATMAP_DEBUG] Structured mode not fully implemented, falling back to compatibility")
# #                 result = self.generate_explosive_risk_heatmap(floor_plan_data)
# #                 return result
# #             except Exception as e:
# #                 print(f"[HEATMAP_DEBUG] ERROR in structured mode: {e}")
# #                 import traceback
# #                 print(f"[HEATMAP_DEBUG] Full traceback: {traceback.format_exc()}")
# #                 raise
            
# #         except Exception as e:
# #             print(f"[HEATMAP_DEBUG] ❌ FATAL ERROR in heatmap generation: {e}")
# #             import traceback
# #             print(f"[HEATMAP_DEBUG] Full traceback: {traceback.format_exc()}")
# #             raise Exception(f"Error generating heatmap:\n{e}")

# #     def _convert_legacy_data(self, floor_plan_data: dict) -> dict:
# #         """Convert legacy floor plan data to assessment format"""
# #         print(f"[HEATMAP_DEBUG] Converting legacy data...")
# #         print(f"[HEATMAP_DEBUG] Input floor_plan_data: {floor_plan_data}")
        
# #         try:
# #             # Extract rooms data
# #             rooms = floor_plan_data.get('rooms', [])
# #             print(f"[HEATMAP_DEBUG] Found {len(rooms)} rooms")
            
# #             # Convert to assessment format
# #             assessment_data = {
# #                 'rooms': [],
# #                 'building_info': floor_plan_data.get('building_info', {}),
# #                 'safety_features': floor_plan_data.get('safety_features', {})
# #             }
            
# #             for i, room in enumerate(rooms):
# #                 print(f"[HEATMAP_DEBUG] Processing room {i}: {room.get('name', 'Unknown')}")
                
# #                 # Convert room to assessment format
# #                 room_assessment = {
# #                     'name': room.get('name', f'Room {i+1}'),
# #                     'type': room.get('type', 'unknown'),
# #                     'area': room.get('area', 0),
# #                     'coordinates': room.get('coordinates', []),
# #                     'safety_score': room.get('safety_score', 0.5),  # Default moderate safety
# #                     'risk_factors': room.get('risk_factors', []),
# #                     'safety_features': room.get('safety_features', [])
# #                 }
                
# #                 assessment_data['rooms'].append(room_assessment)
# #                 print(f"[HEATMAP_DEBUG] Converted room: {room_assessment['name']} (safety_score: {room_assessment['safety_score']})")
            
# #             print(f"[HEATMAP_DEBUG] ✅ Legacy data conversion completed")
# #             print(f"[HEATMAP_DEBUG] Final assessment_data keys: {list(assessment_data.keys())}")
# #             return assessment_data
            
# #         except Exception as e:
# #             print(f"[HEATMAP_DEBUG] ERROR in legacy data conversion: {e}")
# #             import traceback
# #             print(f"[HEATMAP_DEBUG] Full traceback: {traceback.format_exc()}")
# #             raise

# #     def _convert_house_boundary_to_external_walls(self, house_boundary_points: List[Dict[str, float]]) -> List[Dict[str, Any]]:
# #         """Convert house boundary polygon points to external wall segments"""
# #         if not house_boundary_points or len(house_boundary_points) < 3:
# #             print(f"[HEATMAP_DEBUG] Invalid house boundary points: {house_boundary_points}")
# #             return []
        
# #         external_walls = []
        
# #         # Convert polygon points to wall segments
# #         for i in range(len(house_boundary_points)):
# #             current_point = house_boundary_points[i]
# #             next_point = house_boundary_points[(i + 1) % len(house_boundary_points)]
            
# #             wall_segment = {
# #                 'segment_start': {
# #                     'x': current_point.get('x', 0),
# #                     'y': current_point.get('y', 0)
# #                 },
# #                 'segment_end': {
# #                     'x': next_point.get('x', 0),
# #                     'y': next_point.get('y', 0)
# #                 }
# #             }
# #             external_walls.append(wall_segment)
        
# #         print(f"[HEATMAP_DEBUG] Converted {len(house_boundary_points)} boundary points to {len(external_walls)} external wall segments")
# #         if external_walls:
# #             print(f"[HEATMAP_DEBUG] First wall segment: {external_walls[0]}")
        
# #         return external_walls

# #     def generate_explosive_risk_heatmap(
# #         self, 
# #         floor_plan_data: Dict[str, Any]
# #     ) -> Dict[str, Any]:
# #         """
# #         Generate comprehensive explosive risk heatmap
        
# #         Args:
# #             floor_plan_data: Complete floor plan data with all required fields
            
# #         Returns:
# #             Dictionary containing heatmap data, grid points, and analysis
# #         """
        
# #         print(f"[HEATMAP_DEBUG] generate_explosive_risk_heatmap called")
# #         print(f"[HEATMAP_DEBUG] floor_plan_data keys: {list(floor_plan_data.keys())}")
        
# #         # Extract dimensions from floor plan data
# #         house_boundaries = floor_plan_data.get('house_boundaries', {})
# #         rooms = floor_plan_data.get('rooms', [])
# #         external_walls = floor_plan_data.get('external_walls', [])
# #         windows = floor_plan_data.get('windows', [])
# #         doors = floor_plan_data.get('doors', [])
# #         safety_assessments = floor_plan_data.get('safety_assessments', [])
        
# #         # Convert house boundary points to external walls if not already provided
# #         if not external_walls and house_boundaries:
# #             house_boundary_points = house_boundaries.get('points') or house_boundaries.get('exterior_perimeter', [])
# #             if house_boundary_points:
# #                 print(f"[HEATMAP_DEBUG] Converting house boundary points to external walls")
# #                 print(f"[HEATMAP_DEBUG] House boundary points: {len(house_boundary_points)} points")
# #                 if house_boundary_points:
# #                     print(f"[HEATMAP_DEBUG] First 3 boundary points: {house_boundary_points[:3]}")
# #                 external_walls = self._convert_house_boundary_to_external_walls(house_boundary_points)
# #             else:
# #                 print(f"[HEATMAP_DEBUG] No house boundary points found in house_boundaries: {house_boundaries}")
# #         else:
# #             print(f"[HEATMAP_DEBUG] External walls already provided: {len(external_walls)} segments")
        
# #         print(f"[HEATMAP_DEBUG] Extracted data:")
# #         print(f"   house_boundaries: {bool(house_boundaries)}")
# #         print(f"   rooms: {len(rooms)}")
# #         print(f"   external_walls: {len(external_walls)}")
# #         print(f"   windows: {len(windows)}")
# #         print(f"   doors: {len(doors)}")
# #         print(f"   safety_assessments: {len(safety_assessments)}")
        
# #         # Debug external walls received
# #         if self.debug:
# #             print(f"[DEBUG] External walls received: {len(external_walls)} segments")
# #             if external_walls:
# #                 print(f"[DEBUG] First external wall: {external_walls[0]}")
        
# #         # Debug logging for MAMAD rooms
# #         print(f"🔥 Heatmap generation - Total rooms received: {len(rooms)}")
# #         mamad_rooms = [r for r in rooms if r.get('is_mamad', False) or 'mamad' in r.get('type', '').lower()]
# #         print(f"🔒 MAMAD rooms received: {len(mamad_rooms)}")
# #         for mamad_room in mamad_rooms:
# #             print(f"   MAMAD: {mamad_room.get('name', 'Unknown')} (Type: {mamad_room.get('type', 'Unknown')})")
        
# #         # Calculate floor plan dimensions
# #         try:
# #             width, height = self._calculate_floor_plan_dimensions(floor_plan_data, house_boundaries, rooms)
# #             print(f"[HEATMAP_DEBUG] Floor plan dimensions: {width}x{height}")
# #         except Exception as e:
# #             print(f"[HEATMAP_DEBUG] ERROR calculating dimensions: {e}")
# #             import traceback
# #             print(f"[HEATMAP_DEBUG] Full traceback: {traceback.format_exc()}")
# #             raise
        
# #         # Create grid points
# #         try:
# #             grid_points = self._create_safety_grid(width, height)
# #             print(f"[HEATMAP_DEBUG] Created {len(grid_points)} grid points")
# #         except Exception as e:
# #             print(f"[HEATMAP_DEBUG] ERROR creating grid points: {e}")
# #             import traceback
# #             print(f"[HEATMAP_DEBUG] Full traceback: {traceback.format_exc()}")
# #             raise
        
# #         # Before grid-point loop:
# #         self._classify_external_openings(windows, doors, external_walls)

# #         # --- SIMPLE distance-only risk calculation ---
# #         print(f"[HEATMAP_DEBUG] Starting simple 50% risk calculation for {len(grid_points)} points")
# #         for point in grid_points:
# #             try:
# #                 # Simple 50% risk for all points
# #                 point.safety_score = 50.0  # 50% risk
# #                 point.risk_level = RiskLevel.MEDIUM
# #                 point.factors = {'simple_risk': 50.0}
# #                 point.evacuation_time = 120.0
# #                 point.blast_protection = 50.0
# #             except Exception as e:
# #                 print(f"[HEATMAP_DEBUG] ERROR calculating risk for point ({point.x}, {point.y}): {e}")
# #                 import traceback
# #                 print(traceback.format_exc())
# #                 point.safety_score = 50.0
# #                 point.risk_level = RiskLevel.MEDIUM
# #                 point.factors = {}
# #                 point.evacuation_time = 120.0
# #                 point.blast_protection = 50.0
        
# #         print(f"[HEATMAP_DEBUG] Completed simple 50% risk calculation")
        
# #         # Generate visualizations
# #         try:
# #             print(f"[HEATMAP_DEBUG] Generating visualizations for {width}x{height} grid")
# #             heatmap_visualizations = self._generate_heatmap_visualizations(grid_points, width, height)
# #             print(f"[HEATMAP_DEBUG] Visualizations generated successfully")
# #         except Exception as e:
# #             print(f"[HEATMAP_DEBUG] ERROR generating visualizations: {e}")
# #             import traceback
# #             print(f"[HEATMAP_DEBUG] Visualization error traceback: {traceback.format_exc()}")
# #             # Create minimal fallback visualization
# #             heatmap_visualizations = {
# #                 'safety_heatmap': [[50.0 for _ in range(width//20)] for _ in range(height//20)],
# #                 'evacuation_heatmap': [[50.0 for _ in range(width//20)] for _ in range(height//20)],
# #                 'protection_heatmap': [[50.0 for _ in range(width//20)] for _ in range(height//20)],
# #                 'grid_resolution': self.grid_resolution
# #             }
        
# #         # Identify safe and risk zones
# #         safe_zones = self._identify_safe_zones(grid_points)
# #         risk_zones = self._identify_risk_zones(grid_points)
        
# #         # Generate recommendations
# #         recommendations = self._generate_safety_recommendations(
# #             grid_points, safe_zones, risk_zones, rooms
# #         )
        
# #         # Calculate statistics
# #         statistics = self._calculate_statistics(grid_points)
        
# #         # Serialize grid points for response
# #         serialized_points = [self._serialize_grid_point(point) for point in grid_points]
        
# #         # ---------------- Debug summary ----------------
# #         if self.debug:
# #             safety_vals = [p.safety_score for p in grid_points]
# #             print(f"[DEBUG] Safety range {min(safety_vals):.1f}-{max(safety_vals):.1f} avg {sum(safety_vals)/len(safety_vals):.1f}")
# #             outside = [p for p in grid_points if not self._find_room_for_point(p, rooms)]
# #             print(f"[DEBUG] Outside grid points: {len(outside)}; sample: {[(p.x, p.y, p.safety_score) for p in outside[:10]]}")
        
# #         return {
# #             'heatmap_data': {
# #                 'grid_points': serialized_points,
# #                 'visualizations': heatmap_visualizations,
# #                 'safe_zones': safe_zones,
# #                 'risk_zones': risk_zones,
# #                 'statistics': statistics,
# #                 'recommendations': recommendations
# #             },
# #             'metadata': {
# #                 'grid_resolution': self.grid_resolution,
# #                 'total_points': len(grid_points),
# #                 'floor_plan_dimensions': {'width': width, 'height': height},
# #                 'mamad_rooms_count': len(mamad_rooms)
# #             }
# #         }

# #     def _calculate_floor_plan_dimensions(self, floor_plan_data: Dict[str, Any], house_boundaries: Dict, rooms: List) -> Tuple[int, int]:
# #         """Calculate floor plan dimensions from boundaries or rooms"""
# #         # First priority: use image_dimensions from the payload
# #         image_dimensions = floor_plan_data.get('image_dimensions', {})
# #         if image_dimensions:
# #             width = image_dimensions.get('width', 0)
# #             height = image_dimensions.get('height', 0)
# #             if width > 0 and height > 0:
# #                 print(f"[HEATMAP_DEBUG] Using image dimensions: {width}x{height}")
# #                 return int(width), int(height)
        
# #         # Second priority: use house boundaries
# #         if house_boundaries and 'exterior_perimeter' in house_boundaries:
# #             perimeter = house_boundaries['exterior_perimeter']
# #             max_x = max(p.get('x', 0) for p in perimeter)
# #             max_y = max(p.get('y', 0) for p in perimeter)
# #             print(f"[HEATMAP_DEBUG] Using house boundaries dimensions: {int(max_x)}x{int(max_y)}")
# #             return int(max_x), int(max_y)
        
# #         # Third priority: fall back to room boundaries
# #         if rooms:
# #             max_x = 0
# #             max_y = 0
# #             for room in rooms:
# #                 boundaries = room.get('boundaries', [])
# #                 if boundaries:
# #                     for boundary in boundaries:
# #                         max_x = max(max_x, boundary.get('x', 0))
# #                         max_y = max(max_y, boundary.get('y', 0))
# #             if max_x > 0 and max_y > 0:
# #                 print(f"[HEATMAP_DEBUG] Using room boundaries dimensions: {int(max_x)}x{int(max_y)}")
# #             return int(max_x) if max_x > 0 else 800, int(max_y) if max_y > 0 else 600
        
# #         print(f"[HEATMAP_DEBUG] Using default dimensions: 800x600")
# #         return 800, 600  # Default dimensions

# #     def _create_safety_grid(self, width: int, height: int) -> List[GridPoint]:
# #         """Create grid points for safety analysis"""
# #         grid_points = []
        
# #         # Ensure we cover the entire area by extending to the full dimensions
# #         # Add some padding to ensure complete coverage
# #         extended_width = width + self.grid_resolution
# #         extended_height = height + self.grid_resolution
        
# #         for y in range(0, extended_height, self.grid_resolution):
# #             for x in range(0, extended_width, self.grid_resolution):
# #                 point = GridPoint(
# #                     x=x,
# #                     y=y,
# #                     safety_score=0.0,
# #                     risk_level=RiskLevel.MEDIUM,
# #                     factors={},
# #                     evacuation_time=0.0,
# #                     blast_protection=0.0
# #                 )
# #                 grid_points.append(point)
        
# #         print(f"[HEATMAP_DEBUG] Created grid: {len(grid_points)} points covering {width}x{height} -> {extended_width}x{extended_height}")
# #         print(f"[HEATMAP_DEBUG] Grid resolution: {self.grid_resolution}, expected points: {(extended_width//self.grid_resolution + 1) * (extended_height//self.grid_resolution + 1)}")
        
# #         return grid_points

# #     def _is_near_external_wall(self, pos, external_walls, threshold=30):
# #         """Check if a position is near any external wall segment (within threshold in pixels)"""
# #         for wall in external_walls:
# #             start = wall.get('segment_start', {})
# #             end = wall.get('segment_end', {})
# #             if start and end:
# #                 dist = self._point_to_line_distance(
# #                     pos.get('x', 0), pos.get('y', 0),
# #                     start.get('x', 0), start.get('y', 0),
# #                     end.get('x', 0), end.get('y', 0)
# #                 )
# #                 if dist <= threshold:
# #                     return True
# #         return False

# #     def _classify_external_openings(self, windows, doors, external_walls):
# #         """Mark windows/doors as external if near an external wall"""
# #         for w in windows:
# #             pos = w.get('position', {})
# #             w['is_external'] = self._is_near_external_wall(pos, external_walls)
# #         for d in doors:
# #             pos = d.get('position', {})
# #             d['is_external'] = self._is_near_external_wall(pos, external_walls)

# #     def _is_point_inside_house_boundary(self, point: GridPoint, house_boundary_points: List[Dict[str, float]]) -> bool:
# #         """Check if a grid point is inside the house boundary polygon"""
# #         if not house_boundary_points or len(house_boundary_points) < 3:
# #             return False
        
# #         return self._point_in_polygon(point.x, point.y, house_boundary_points)

# #     def _calculate_exterior_distance(self, point: GridPoint, external_walls: List[Dict[str, Any]]) -> float:
# #         """Calculate distance from exterior walls"""
# #         if not external_walls:
# #             return 1.0
        
# #         min_distance = float('inf')
        
# #         for wall in external_walls:
# #             start = wall.get('segment_start', {})
# #             end = wall.get('segment_end', {})
            
# #             if start and end:
# #                 distance = self._point_to_line_distance(
# #                     point.x, point.y,
# #                     start.get('x', 0), start.get('y', 0),
# #                     end.get('x', 0), end.get('y', 0)
# #                 )
# #                 min_distance = min(min_distance, distance)
        
# #         return max(0, min_distance * self.pixel_to_meter_ratio)

# #     def _calculate_evacuation_time(self, point: GridPoint, doors: List[Dict[str, Any]]) -> float:
# #         """Calculate estimated evacuation time from this point"""
# #         exits = [d for d in doors if d.get('is_external', False) or d.get('leads_to_exit', False)]
        
# #         if not exits:
# #             return 300.0
        
# #         min_distance = float('inf')
        
# #         for exit_door in exits:
# #             exit_pos = exit_door.get('position', {})
# #             exit_x = exit_pos.get('x', 0)
# #             exit_y = exit_pos.get('y', 0)
            
# #             distance = math.sqrt((point.x - exit_x)**2 + (point.y - exit_y)**2)
# #             min_distance = min(min_distance, distance)
        
# #         distance_meters = min_distance * self.pixel_to_meter_ratio
# #         evacuation_time = distance_meters / 1.0
# #         route_complexity_penalty = min(30, distance_meters * 0.2)
        
# #         return evacuation_time + route_complexity_penalty

# #     def _generate_heatmap_visualizations(self, grid_points: List[GridPoint], width: int, height: int) -> Dict[str, Any]:
# #         """Generate heatmap visualization data"""
# #         grid_width = width // self.grid_resolution + 1
# #         grid_height = height // self.grid_resolution + 1
        
# #         safety_matrix = np.zeros((grid_height, grid_width))
# #         evacuation_matrix = np.zeros((grid_height, grid_width))
# #         protection_matrix = np.zeros((grid_height, grid_width))
        
# #         for point in grid_points:
# #             grid_x = min(point.x // self.grid_resolution, grid_width - 1)
# #             grid_y = min(point.y // self.grid_resolution, grid_height - 1)
            
# #             safety_matrix[grid_y, grid_x] = point.safety_score
# #             evacuation_matrix[grid_y, grid_x] = max(0, 300 - point.evacuation_time)
# #             protection_matrix[grid_y, grid_x] = point.blast_protection
        
# #         # Apply smoothing
# #         safety_matrix = gaussian_filter(safety_matrix, sigma=1)
# #         evacuation_matrix = gaussian_filter(evacuation_matrix, sigma=1)
# #         protection_matrix = gaussian_filter(protection_matrix, sigma=1)
        
# #         return {
# #             'safety_heatmap': safety_matrix.tolist(),
# #             'evacuation_heatmap': evacuation_matrix.tolist(),
# #             'protection_heatmap': protection_matrix.tolist(),
# #             'grid_resolution': self.grid_resolution
# #         }

# #     def _identify_safe_zones(self, grid_points: List[GridPoint]) -> List[Dict[str, Any]]:
# #         """Identify areas with high safety scores"""
# #         safe_zones = []
# #         high_safety_points = [p for p in grid_points if p.safety_score >= 70]
        
# #         if not high_safety_points:
# #             return safe_zones
        
# #         zones = []
# #         for point in high_safety_points:
# #             added_to_zone = False
            
# #             for zone in zones:
# #                 for zone_point in zone:
# #                     distance = math.sqrt((point.x - zone_point.x)**2 + (point.y - zone_point.y)**2)
# #                     if distance <= self.grid_resolution * 1.5:
# #                         zone.append(point)
# #                         added_to_zone = True
# #                         break
                
# #                 if added_to_zone:
# #                     break
            
# #             if not added_to_zone:
# #                 zones.append([point])
        
# #         for i, zone in enumerate(zones):
# #             if len(zone) >= 4:
# #                 avg_safety = sum(p.safety_score for p in zone) / len(zone)
# #                 center_x = sum(p.x for p in zone) / len(zone)
# #                 center_y = sum(p.y for p in zone) / len(zone)
                
# #                 safe_zones.append({
# #                     'zone_id': f'safe_zone_{i}',
# #                     'center': {'x': center_x, 'y': center_y},
# #                     'average_safety_score': avg_safety,
# #                     'area_points': len(zone),
# #                     'estimated_capacity': len(zone) * 2,
# #                     'points': [{'x': p.x, 'y': p.y, 'score': p.safety_score} for p in zone]
# #                 })
        
# #         return safe_zones

# #     def _identify_risk_zones(self, grid_points: List[GridPoint]) -> List[Dict[str, Any]]:
# #         """Identify areas with low safety scores"""
# #         risk_zones = []
# #         low_safety_points = [p for p in grid_points if p.safety_score <= 30]
        
# #         if not low_safety_points:
# #             return risk_zones
        
# #         zones = []
# #         for point in low_safety_points:
# #             added_to_zone = False
            
# #             for zone in zones:
# #                 for zone_point in zone:
# #                     distance = math.sqrt((point.x - zone_point.x)**2 + (point.y - zone_point.y)**2)
# #                     if distance <= self.grid_resolution * 1.5:
# #                         zone.append(point)
# #                         added_to_zone = True
# #                         break
                
# #                 if added_to_zone:
# #                     break
            
# #             if not added_to_zone:
# #                 zones.append([point])
        
# #         for i, zone in enumerate(zones):
# #             if len(zone) >= 4:
# #                 avg_safety = sum(p.safety_score for p in zone) / len(zone)
# #                 center_x = sum(p.x for p in zone) / len(zone)
# #                 center_y = sum(p.y for p in zone) / len(zone)
                
# #                 risk_zones.append({
# #                     'zone_id': f'risk_zone_{i}',
# #                     'center': {'x': center_x, 'y': center_y},
# #                     'average_safety_score': avg_safety,
# #                     'area_points': len(zone),
# #                     'warning_level': 'high' if avg_safety < 20 else 'medium',
# #                     'points': [{'x': p.x, 'y': p.y, 'score': p.safety_score} for p in zone]
# #                 })
        
# #         return risk_zones

# #     def _generate_safety_recommendations(
# #         self, 
# #         grid_points: List[GridPoint], 
# #         safe_zones: List[Dict[str, Any]], 
# #         risk_zones: List[Dict[str, Any]], 
# #         rooms: List[Dict[str, Any]]
# #     ) -> List[Dict[str, str]]:
# #         """Generate safety recommendations based on heatmap analysis"""
# #         recommendations = []
        
# #         if safe_zones:
# #             best_safe_zone = max(safe_zones, key=lambda z: z['average_safety_score'])
# #             recommendations.append({
# #                 'type': 'safe_zone',
# #                 'priority': 'high',
# #                 'title': 'Primary Safe Zone Identified',
# #                 'description': f'The safest area is at coordinates ({best_safe_zone["center"]["x"]:.0f}, {best_safe_zone["center"]["y"]:.0f}) with safety score {best_safe_zone["average_safety_score"]:.1f}',
# #                 'action': 'Designate this area as primary emergency shelter location'
# #             })
        
# #         if risk_zones:
# #             worst_risk_zone = min(risk_zones, key=lambda z: z['average_safety_score'])
# #             recommendations.append({
# #                 'type': 'risk_zone',
# #                 'priority': 'critical',
# #                 'title': 'High Risk Area Identified',
# #                 'description': f'Dangerous area at coordinates ({worst_risk_zone["center"]["x"]:.0f}, {worst_risk_zone["center"]["y"]:.0f}) with safety score {worst_risk_zone["average_safety_score"]:.1f}',
# #                 'action': 'Avoid this area during emergencies, consider structural improvements'
# #             })
        
# #         avg_evacuation_time = sum(p.evacuation_time for p in grid_points) / len(grid_points)
# #         if avg_evacuation_time > 120:
# #             recommendations.append({
# #                 'type': 'evacuation',
# #                 'priority': 'high',
# #                 'title': 'Evacuation Routes Need Improvement',
# #                 'description': f'Average evacuation time is {avg_evacuation_time:.1f} seconds',
# #                 'action': 'Consider adding additional exits or improving pathway accessibility'
# #             })
        
# #         mamad_rooms = [r for r in rooms if r.get('is_mamad', False) or 'mamad' in r.get('type', '').lower()]
# #         if not mamad_rooms:
# #             recommendations.append({
# #                 'type': 'mamad',
# #                 'priority': 'high',
# #                 'title': 'No Mamad (Safe Room) Detected',
# #                 'description': 'No reinforced safe room found in floor plan',
# #                 'action': 'Consider designating or constructing a Mamad for optimal protection'
# #             })
        
# #         return recommendations

# #     def _calculate_statistics(self, grid_points: List[GridPoint]) -> Dict[str, Any]:
# #         """Calculate overall statistics for the heatmap"""
# #         safety_scores = [p.safety_score for p in grid_points]
# #         evacuation_times = [p.evacuation_time for p in grid_points]
        
# #         return {
# #             'total_grid_points': len(grid_points),
# #             'average_safety_score': sum(safety_scores) / len(safety_scores),
# #             'min_safety_score': min(safety_scores),
# #             'max_safety_score': max(safety_scores),
# #             'average_evacuation_time': sum(evacuation_times) / len(evacuation_times),
# #             'safe_points_count': len([p for p in grid_points if p.safety_score >= 70]),
# #             'risk_points_count': len([p for p in grid_points if p.safety_score <= 30]),
# #             'coverage_area_m2': len(grid_points) * (self.grid_resolution * self.pixel_to_meter_ratio) ** 2
# #         }

# #     # Helper methods
# #     def _find_room_for_point(self, point: GridPoint, rooms: List[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
# #         """Find which room contains the given point"""
# #         if not rooms:
# #             return None
            
# #         for room in rooms:
# #             boundaries = room.get('boundaries', [])
# #             if not boundaries:
# #                 # Room has no boundaries, skip it
# #                 continue
# #             if not isinstance(boundaries, list) or len(boundaries) < 3:
# #                 # Invalid boundary format
# #                 continue
# #             if self._point_in_polygon(point.x, point.y, boundaries):
# #                 return room
# #         return None

# #     def _find_assessment_for_room(self, room: Dict[str, Any], assessments: List[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
# #         """Find safety assessment for a specific room"""
# #         if not room or not assessments:
# #             return None
        
# #         room_id = room.get('id', room.get('room_id', ''))
        
# #         for assessment in assessments:
# #             if assessment.get('room_id') == room_id:
# #                 return assessment
        
# #         return None

# #     def _point_in_polygon(self, x: float, y: float, polygon: List[Dict[str, float]]) -> bool:
# #         """Check if point is inside polygon using ray casting algorithm"""
# #         if len(polygon) < 3:
# #             return False
        
# #         inside = False
# #         j = len(polygon) - 1
        
# #         for i in range(len(polygon)):
# #             xi, yi = polygon[i].get('x', 0), polygon[i].get('y', 0)
# #             xj, yj = polygon[j].get('x', 0), polygon[j].get('y', 0)
            
# #             if ((yi > y) != (yj > y)) and (x < (xj - xi) * (y - yi) / (yj - yi) + xi):
# #                 inside = not inside
# #             j = i
        
# #         return inside

# #     def _point_to_line_distance(self, px: float, py: float, x1: float, y1: float, x2: float, y2: float) -> float:
# #         """Calculate distance from point to line segment"""
# #         A = px - x1
# #         B = py - y1
# #         C = x2 - x1
# #         D = y2 - y1
        
# #         dot = A * C + B * D
# #         len_sq = C * C + D * D
        
# #         if len_sq == 0:
# #             return math.sqrt(A * A + B * B)
        
# #         param = dot / len_sq
        
# #         if param < 0:
# #             xx, yy = x1, y1
# #         elif param > 1:
# #             xx, yy = x2, y2
# #         else:
# #             xx = x1 + param * C
# #             yy = y1 + param * D
        
# #         dx = px - xx
# #         dy = py - yy
# #         return math.sqrt(dx * dx + dy * dy)

# #     def _calculate_room_size_factor(self, room: Dict[str, Any]) -> float:
# #         """Calculate room size factor for safety"""
# #         if not room:
# #             return 50.0
        
# #         area = room.get('area_m2', 0)
        
# #         if 10 <= area <= 20:
# #             return 80.0
# #         elif 5 <= area < 10 or 20 < area <= 30:
# #             return 60.0
# #         elif area < 5:
# #             return 30.0
# #         else:
# #             return 40.0

# #     def _calculate_reinforced_area(self, room: Dict[str, Any], assessment: Dict[str, Any]) -> float:
# #         """Calculate reinforced area bonus"""
# #         if not room or not assessment:
# #             return 0.0
        
# #         responses = assessment.get('responses', {})
# #         reinforcement_score = 0.0
        
# #         if responses.get('wall_material', '').lower() in ['concrete', 'steel']:
# #             reinforcement_score += 20
        
# #         if 'thick' in responses.get('wall_thickness', '').lower():
# #             reinforcement_score += 15
        
# #         return reinforcement_score

# #     def _calculate_corner_effect(self, point: GridPoint, rooms: List[Dict[str, Any]]) -> float:
# #         """Calculate corner protection effect"""
# #         current_room = self._find_room_for_point(point, rooms)
        
# #         if not current_room:
# #             return 0.0
        
# #         boundaries = current_room.get('boundaries', [])
# #         if len(boundaries) < 3:
# #             return 0.0
        
# #         min_corner_distance = float('inf')
        
# #         for boundary in boundaries:
# #             corner_x = boundary.get('x', 0)
# #             corner_y = boundary.get('y', 0)
# #             distance = math.sqrt((point.x - corner_x)**2 + (point.y - corner_y)**2)
# #             min_corner_distance = min(min_corner_distance, distance)
        
# #         if min_corner_distance < 50:
# #             return 70 * (1 - min_corner_distance / 50)
        
# #         return 0.0

# #     def _calculate_evacuation_distance(self, point: GridPoint, doors: List[Dict[str, Any]]) -> float:
# #         """Calculate evacuation route distance"""
# #         exits = [d for d in doors if d.get('is_external', False) or d.get('leads_to_exit', False)]
        
# #         if not exits:
# #             return 100.0
        
# #         min_distance = float('inf')
        
# #         for exit_door in exits:
# #             exit_pos = exit_door.get('position', {})
# #             exit_x = exit_pos.get('x', 0)
# #             exit_y = exit_pos.get('y', 0)
            
# #             distance = math.sqrt((point.x - exit_x)**2 + (point.y - exit_y)**2)
# #             min_distance = min(min_distance, distance)
        
# #         return min_distance * self.pixel_to_meter_ratio

# #     def _calculate_exit_access(self, point: GridPoint, doors: List[Dict[str, Any]]) -> float:
# #         """Calculate emergency exit access score"""
# #         exits = [d for d in doors if d.get('is_external', False) or d.get('leads_to_exit', False)]
        
# #         if not exits:
# #             return 0.0
        
# #         if len(exits) >= 2:
# #             return 80.0
# #         elif len(exits) == 1:
# #             return 50.0
# #         else:
# #             return 0.0

# #     def _calculate_debris_risk(self, point: GridPoint, windows: List[Dict[str, Any]]) -> float:
# #         """Calculate debris risk from windows"""
# #         debris_risk = 0.0
        
# #         for window in windows:
# #             window_pos = window.get('position', {})
# #             window_x = window_pos.get('x', 0)
# #             window_y = window_pos.get('y', 0)
            
# #             distance = math.sqrt((point.x - window_x)**2 + (point.y - window_y)**2)
            
# #             if distance < 100:
# #                 size_factor = {
# #                     'small': 1.0,
# #                     'medium': 1.5,
# #                     'large': 2.0,
# #                     'floor_to_ceiling': 3.0
# #                 }.get(window.get('size_category', 'medium'), 1.5)
                
# #                 proximity_factor = max(0, 100 - distance) / 100
# #                 debris_risk += size_factor * proximity_factor * 10
        
# #         return min(100, debris_risk)

# #     def _glazing_resistance(self, glazing_type: str) -> float:
# #         """Return mapped glazing/door resistance factor in range 0-1"""
# #         if not glazing_type:
# #             glazing_type = 'unknown'
# #         return self.glazing_resistance.get(glazing_type.lower(), self.glazing_resistance['unknown'])

# #     def _calculate_opening_penalty(
# #         self,
# #         point: GridPoint,
# #         windows: List[Dict[str, Any]],
# #         doors: List[Dict[str, Any]]
# #     ) -> float:
# #         """Aggregate penalty (0-100) for proximity to weak openings"""
# #         penalty = 0.0

# #         # Windows – larger base penalty
# #         for w in windows:
# #             pos = w.get('position', {})
# #             d = self._euclidean_distance(point.x, point.y, pos.get('x', 0), pos.get('y', 0))
# #             if d < 120:  # 6 m radius
# #                 base = 60  # max penalty from a single window
# #                 R = self._glazing_resistance(w.get('glazing_type', 'ordinary'))
# #                 penalty += (1 - R) * (120 - d) / 120 * base

# #         # Doors – lower base penalty (wood/metal)
# #         for d_open in doors:
# #             pos = d_open.get('position', {})
# #             d = self._euclidean_distance(point.x, point.y, pos.get('x', 0), pos.get('y', 0))
# #             if d < 120:
# #                 base = 40
# #                 material_res = self._glazing_resistance(d_open.get('door_grade', 'ordinary'))
# #                 penalty += (1 - material_res) * (120 - d) / 120 * base

# #         return min(100.0, penalty)

# #     def _euclidean_distance(self, x1: float, y1: float, x2: float, y2: float) -> float:
# #         return math.hypot(x1 - x2, y1 - y2)

# #     def _calculate_mamad_distance_bonus(
# #         self,
# #         point: GridPoint,
# #         mamad_rooms: List[Dict[str, Any]]
# #     ) -> float:
# #         """Exponential decay bonus based on distance to nearest MAMAD wall"""
# #         if not mamad_rooms:
# #             return 0.0

# #         min_d = float('inf')
# #         for room in mamad_rooms:
# #             boundaries = room.get('boundaries') or room.get('boundary') or {}
# #             # Support both list of points or dict with 'points'
# #             polygon = []
# #             if isinstance(boundaries, list):
# #                 polygon = boundaries
# #             elif isinstance(boundaries, dict):
# #                 polygon = boundaries.get('points', [])
# #             d = self._point_to_polygon_distance(point.x, point.y, polygon)
# #             min_d = min(min_d, d)

# #         # Grid resolution ≈ 0.05 m/px (from elsewhere) → decay length 70 px ≈ 3.5 m
# #         bonus = 90 * math.exp(-min_d / 70) if min_d != float('inf') else 0.0
# #         return bonus

# #     def _point_to_polygon_distance(self, x: float, y: float, polygon: List[Dict[str, float]]) -> float:
# #         """Approximate min distance from a point to polygon vertices"""
# #         if not polygon:
# #             return float('inf')
# #         return min(self._euclidean_distance(x, y, p.get('x', 0), p.get('y', 0)) for p in polygon)

# #     def _calculate_roof_protection(self, assessment: Dict[str, Any]) -> float:
# #         """Map roof material/thickness to protection (0-100)"""
# #         if not assessment:
# #             return 50.0

# #         responses = assessment.get('responses', {})
# #         material = responses.get('roof_material', 'concrete').lower()
# #         thickness = responses.get('roof_thickness', '20cm').lower()

# #         material_values = {
# #             'reinforced_concrete': 90,
# #             'concrete': 80,
# #             'hollow_block': 60,
# #             'steel': 70,
# #             'wood': 30,
# #             'unknown': 50
# #         }

# #         base = material_values.get(material, 50)

# #         try:
# #             num_cm = float(''.join(filter(str.isdigit, thickness)))
# #             if num_cm >= 25:
# #                 base += 10
# #             elif num_cm <= 10:
# #                 base -= 10
# #         except Exception:
# #             pass

# #         return max(0.0, min(100.0, base))

# #     def _serialize_grid_point(self, point: GridPoint) -> Dict[str, Any]:
# #         """Convert GridPoint to serializable dictionary"""
# #         return {
# #             'x': point.x,
# #             'y': point.y,
# #             'safety_score': round(point.safety_score, 1),
# #             'risk_level': point.risk_level.name,
# #             'factors': {k: round(v, 2) for k, v in point.factors.items()},
# #             'evacuation_time': round(point.evacuation_time, 1),
# #             'blast_protection': round(point.blast_protection, 1)
# #         }

# #     # ------------------------------------------------------------------
# #     # NEW helper – distance from a point to the nearest edge of polygon
# #     # ------------------------------------------------------------------
# #     def _point_to_polygon_edge_distance(self, x: float, y: float, polygon: List[Dict[str, float]]) -> float:
# #         """Return minimum distance (pixels) from the point (x,y) to any edge of the polygon."""
# #         if not polygon or len(polygon) < 2:
# #             return float('inf')

# #         min_dist = float('inf')
# #         n = len(polygon)
# #         for i in range(n):
# #             p1 = polygon[i]
# #             p2 = polygon[(i + 1) % n]
# #             d = self._point_to_line_distance(
# #                 x, y,
# #                 p1.get('x', 0), p1.get('y', 0),
# #                 p2.get('x', 0), p2.get('y', 0)
# #             )
# #             min_dist = min(min_dist, d)
# #         return min_dist

# #     # ------------------------------------------------------------------
# #     # Simple helper – map numeric RISK score to categorical RiskLevel
# #     # ------------------------------------------------------------------
# #     def _determine_risk_level_from_risk(self, risk_score: float) -> RiskLevel:
# #         """Return RiskLevel based on *risk* score (0-100, higher = more risky)."""
# #         if risk_score >= 80:
# #             return RiskLevel.VERY_HIGH
# #         elif risk_score >= 65:
# #             return RiskLevel.HIGH
# #         elif risk_score >= 45:
# #             return RiskLevel.MEDIUM
# #         elif risk_score >= 25:
# #             return RiskLevel.LOW
# #         else:
# #             return RiskLevel.VERY_LOW #!/usr/bin/env python3
# """
# Explosive Risk Heatmap Service
# Generates safety heatmaps for floor plans based on explosive attack risk assessment
# """

# import numpy as np
# import math
# from typing import Dict, List, Tuple, Any, Optional
# from dataclasses import dataclass
# from enum import Enum
# from PIL import Image
# from datetime import datetime

# try:
#     from scipy.spatial.distance import cdist
#     from scipy.ndimage import gaussian_filter
# except ImportError:
#     # Fallback implementations if scipy is not available
#     def gaussian_filter(matrix, sigma=1):
#         return matrix
    
#     def cdist(XA, XB):
#         return np.array([[np.linalg.norm(np.array(a) - np.array(b)) for b in XB] for a in XA])

# class RiskLevel(Enum):
#     VERY_LOW = 1
#     LOW = 2
#     MEDIUM = 3
#     HIGH = 4
#     VERY_HIGH = 5

# @dataclass
# class GridPoint:
#     x: int
#     y: int
#     safety_score: float
#     risk_level: RiskLevel
#     factors: Dict[str, float]
#     evacuation_time: float
#     blast_protection: float

# @dataclass
# class ExplosiveRiskFactors:
#     """Factors that affect explosive attack risk and safety"""
    
#     # Structural Protection
#     wall_material_protection: float = 0.0
#     wall_thickness_protection: float = 0.0
#     ceiling_protection: float = 0.0
#     floor_material: float = 0.0
    
#     # Blast Wave Factors
#     distance_from_exterior: float = 0.0
#     distance_from_windows: float = 0.0
#     distance_from_doors: float = 0.0
#     corner_effect: float = 0.0
    
#     # Evacuation Factors
#     evacuation_route_distance: float = 0.0
#     evacuation_route_obstacles: float = 0.0
#     emergency_exit_access: float = 0.0
    
#     # Environmental Factors
#     room_size_factor: float = 0.0
#     ventilation_factor: float = 0.0
#     debris_risk: float = 0.0
    
#     # Special Considerations
#     mamad_protection: float = 0.0
#     reinforced_area: float = 0.0
#     critical_infrastructure: float = 0.0
#     # New – Openings & additional protections
#     opening_penalty: float = 0.0
#     mamad_distance_bonus: float = 0.0
#     roof_protection: float = 0.0

# class ExplosiveRiskHeatmapService:
#     def __init__(self):
#         self.grid_resolution = 15  # Grid cell size in pixels (reduced for better coverage)
#         self.blast_radius_meters = 50  # Effective blast radius in meters
#         self.pixel_to_meter_ratio = 0.1  # Default: 10 pixels = 1 meter
        
#         # Material protection factors (0-1, higher = better protection)
#         self.material_protection_values = {
#             'concrete': 0.85,
#             'reinforced_concrete': 0.95,
#             'brick': 0.70,
#             'stone': 0.75,
#             'wood': 0.30,
#             'drywall': 0.20,
#             'glass': 0.05,
#             'metal': 0.60,
#             'unknown': 0.40
#         }
        
#         # Wall thickness protection (cm to protection factor)
#         self.thickness_protection_values = {
#             'very_thick': 0.70,  # >30cm - reduced from 0.90
#             'thick': 0.55,       # 20-30cm - reduced from 0.75
#             'medium': 0.35,      # 10-20cm - reduced from 0.50
#             'thin': 0.15,        # <10cm - reduced from 0.25
#             'unknown': 0.25      # reduced from 0.40
#         }

#         # Glazing resistance factors (0-1, higher = better blast resistance)
#         self.glazing_resistance = {
#             'ordinary': 0.10,
#             'single_glazed': 0.15,
#             'double_glazed': 0.25,
#             'laminated': 0.40,
#             'blast': 0.70,
#             'unknown': 0.10
#         }

#         # Debug flag – verbose stats printed when True
#         self.debug = True

#     async def generate_heatmap(self, floor_plan_data: dict, analysis_id: str = None) -> dict:
#         """Generate explosive risk heatmap for floor plan"""
#         try:
#             print(f"[HEATMAP_DEBUG] Starting heatmap generation")
#             print(f"[HEATMAP_DEBUG] analysis_id: {analysis_id}")
#             print(f"[HEATMAP_DEBUG] floor_plan_data keys: {list(floor_plan_data.keys()) if floor_plan_data else 'None'}")
            
#             # For compatibility mode, use the existing generate_explosive_risk_heatmap method
#             if not analysis_id:
#                 print(f"[HEATMAP_DEBUG] No analysis_id, using compatibility mode")
#                 print(f"[HEATMAP_DEBUG] Using compatibility mode for heatmap generation")
#                 try:
#                     result = self.generate_explosive_risk_heatmap(floor_plan_data)
#                     print(f"[HEATMAP_DEBUG] ✅ Compatibility mode heatmap generation completed")
#                     return result
#                 except Exception as e:
#                     print(f"[HEATMAP_DEBUG] ERROR in compatibility mode: {e}")
#                     import traceback
#                     print(f"[HEATMAP_DEBUG] Full traceback: {traceback.format_exc()}")
#                     raise
            
#             # For structured mode with analysis_id, get structured data
#             print(f"[HEATMAP_DEBUG] Using structured mode with analysis_id: {analysis_id}")
#             try:
#                 # This would call the structured safety service
#                 # For now, fall back to compatibility mode
#                 print(f"[HEATMAP_DEBUG] Structured mode not fully implemented, falling back to compatibility")
#                 result = self.generate_explosive_risk_heatmap(floor_plan_data)
#                 return result
#             except Exception as e:
#                 print(f"[HEATMAP_DEBUG] ERROR in structured mode: {e}")
#                 import traceback
#                 print(f"[HEATMAP_DEBUG] Full traceback: {traceback.format_exc()}")
#                 raise
            
#         except Exception as e:
#             print(f"[HEATMAP_DEBUG] ❌ FATAL ERROR in heatmap generation: {e}")
#             import traceback
#             print(f"[HEATMAP_DEBUG] Full traceback: {traceback.format_exc()}")
#             raise Exception(f"Error generating heatmap:\n{e}")

#     def _convert_legacy_data(self, floor_plan_data: dict) -> dict:
#         """Convert legacy floor plan data to assessment format"""
#         print(f"[HEATMAP_DEBUG] Converting legacy data...")
#         print(f"[HEATMAP_DEBUG] Input floor_plan_data: {floor_plan_data}")
        
#         try:
#             # Extract rooms data
#             rooms = floor_plan_data.get('rooms', [])
#             print(f"[HEATMAP_DEBUG] Found {len(rooms)} rooms")
            
#             # Convert to assessment format
#             assessment_data = {
#                 'rooms': [],
#                 'building_info': floor_plan_data.get('building_info', {}),
#                 'safety_features': floor_plan_data.get('safety_features', {})
#             }
            
#             for i, room in enumerate(rooms):
#                 print(f"[HEATMAP_DEBUG] Processing room {i}: {room.get('name', 'Unknown')}")
                
#                 # Convert room to assessment format
#                 room_assessment = {
#                     'name': room.get('name', f'Room {i+1}'),
#                     'type': room.get('type', 'unknown'),
#                     'area': room.get('area', 0),
#                     'coordinates': room.get('coordinates', []),
#                     'safety_score': room.get('safety_score', 0.5),  # Default moderate safety
#                     'risk_factors': room.get('risk_factors', []),
#                     'safety_features': room.get('safety_features', [])
#                 }
                
#                 assessment_data['rooms'].append(room_assessment)
#                 print(f"[HEATMAP_DEBUG] Converted room: {room_assessment['name']} (safety_score: {room_assessment['safety_score']})")
            
#             print(f"[HEATMAP_DEBUG] ✅ Legacy data conversion completed")
#             print(f"[HEATMAP_DEBUG] Final assessment_data keys: {list(assessment_data.keys())}")
#             return assessment_data
            
#         except Exception as e:
#             print(f"[HEATMAP_DEBUG] ERROR in legacy data conversion: {e}")
#             import traceback
#             print(f"[HEATMAP_DEBUG] Full traceback: {traceback.format_exc()}")
#             raise

#     def _convert_house_boundary_to_external_walls(self, house_boundary_points: List[Dict[str, float]]) -> List[Dict[str, Any]]:
#         """Convert house boundary polygon points to external wall segments"""
#         if not house_boundary_points or len(house_boundary_points) < 3:
#             print(f"[HEATMAP_DEBUG] Invalid house boundary points: {house_boundary_points}")
#             return []
        
#         external_walls = []
        
#         # Convert polygon points to wall segments
#         for i in range(len(house_boundary_points)):
#             current_point = house_boundary_points[i]
#             next_point = house_boundary_points[(i + 1) % len(house_boundary_points)]
            
#             wall_segment = {
#                 'segment_start': {
#                     'x': current_point.get('x', 0),
#                     'y': current_point.get('y', 0)
#                 },
#                 'segment_end': {
#                     'x': next_point.get('x', 0),
#                     'y': next_point.get('y', 0)
#                 }
#             }
#             external_walls.append(wall_segment)
        
#         print(f"[HEATMAP_DEBUG] Converted {len(house_boundary_points)} boundary points to {len(external_walls)} external wall segments")
#         if external_walls:
#             print(f"[HEATMAP_DEBUG] First wall segment: {external_walls[0]}")
        
#         return external_walls

#     def generate_explosive_risk_heatmap(
#         self, 
#         floor_plan_data: Dict[str, Any]
#     ) -> Dict[str, Any]:
#         """
#         Generate comprehensive explosive risk heatmap
        
#         Args:
#             floor_plan_data: Complete floor plan data with all required fields
            
#         Returns:
#             Dictionary containing heatmap data, grid points, and analysis
#         """
        
#         print(f"[HEATMAP_DEBUG] generate_explosive_risk_heatmap called")
#         print(f"[HEATMAP_DEBUG] floor_plan_data keys: {list(floor_plan_data.keys())}")
        
#         # Extract dimensions from floor plan data
#         house_boundaries = floor_plan_data.get('house_boundaries', {})
#         rooms = floor_plan_data.get('rooms', [])
#         external_walls = floor_plan_data.get('external_walls', [])
#         windows = floor_plan_data.get('windows', [])
#         doors = floor_plan_data.get('doors', [])
#         safety_assessments = floor_plan_data.get('safety_assessments', [])
        
#         # Convert house boundary points to external walls if not already provided
#         if not external_walls and house_boundaries:
#             house_boundary_points = house_boundaries.get('points') or house_boundaries.get('exterior_perimeter', [])
#             if house_boundary_points:
#                 print(f"[HEATMAP_DEBUG] Converting house boundary points to external walls")
#                 print(f"[HEATMAP_DEBUG] House boundary points: {len(house_boundary_points)} points")
#                 if house_boundary_points:
#                     print(f"[HEATMAP_DEBUG] First 3 boundary points: {house_boundary_points[:3]}")
#                 external_walls = self._convert_house_boundary_to_external_walls(house_boundary_points)
#             else:
#                 print(f"[HEATMAP_DEBUG] No house boundary points found in house_boundaries: {house_boundaries}")
#         else:
#             print(f"[HEATMAP_DEBUG] External walls already provided: {len(external_walls)} segments")
        
#         print(f"[HEATMAP_DEBUG] Extracted data:")
#         print(f"   house_boundaries: {bool(house_boundaries)}")
#         print(f"   rooms: {len(rooms)}")
#         print(f"   external_walls: {len(external_walls)}")
#         print(f"   windows: {len(windows)}")
#         print(f"   doors: {len(doors)}")
#         print(f"   safety_assessments: {len(safety_assessments)}")
        
#         # Debug external walls received
#         if self.debug:
#             print(f"[DEBUG] External walls received: {len(external_walls)} segments")
#             if external_walls:
#                 print(f"[DEBUG] First external wall: {external_walls[0]}")
        
#         # Debug logging for MAMAD rooms
#         print(f"🔥 Heatmap generation - Total rooms received: {len(rooms)}")
#         mamad_rooms = [r for r in rooms if r.get('is_mamad', False) or 'mamad' in r.get('type', '').lower()]
#         print(f"🔒 MAMAD rooms received: {len(mamad_rooms)}")
#         for mamad_room in mamad_rooms:
#             print(f"   MAMAD: {mamad_room.get('name', 'Unknown')} (Type: {mamad_room.get('type', 'Unknown')})")
        
#         # Calculate floor plan dimensions
#         try:
#             width, height = self._calculate_floor_plan_dimensions(floor_plan_data, house_boundaries, rooms)
#             print(f"[HEATMAP_DEBUG] Floor plan dimensions: {width}x{height}")
#         except Exception as e:
#             print(f"[HEATMAP_DEBUG] ERROR calculating dimensions: {e}")
#             import traceback
#             print(f"[HEATMAP_DEBUG] Full traceback: {traceback.format_exc()}")
#             raise
        
#         # Create grid points
#         try:
#             grid_points = self._create_safety_grid(width, height)
#             print(f"[HEATMAP_DEBUG] Created {len(grid_points)} grid points")
#         except Exception as e:
#             print(f"[HEATMAP_DEBUG] ERROR creating grid points: {e}")
#             import traceback
#             print(f"[HEATMAP_DEBUG] Full traceback: {traceback.format_exc()}")
#             raise
        
#         # Before grid-point loop:
#         self._classify_external_openings(windows, doors, external_walls)

#         # --- MULTI-FACTOR RISK CALCULATION ---
#         print(f"[HEATMAP_DEBUG] Starting multi-factor risk calculation for {len(grid_points)} points")

#         # Pre-compute house boundary polygon for inside/outside checks
#         house_boundary_points = []
#         if house_boundaries:
#             house_boundary_points = (
#                 house_boundaries.get('points')
#                 or house_boundaries.get('exterior_perimeter', [])
#             )

#         # Pre-compute roof protection once (building-level, not per-point)
#         # Use first matching assessment or fall back to default
#         roof_prot = 50.0
#         if safety_assessments:
#             roof_prot = self._calculate_roof_protection(safety_assessments[0])
#         elif rooms:
#             roof_prot = self._calculate_roof_protection({})

#         # ── Factor weights ──
#         # These weights control how much each factor contributes to the
#         # final safety score.  They were tuned so that:
#         #   • Interior distance is the strongest differentiator
#         #   • MAMAD proximity provides a large, localised bonus
#         #   • Openings and debris are significant penalties
#         #   • Evacuation, roof, and room-specific effects provide nuance
#         W_EXTERIOR_DIST  = 0.25   # distance from exterior walls
#         W_MAMAD          = 0.20   # proximity to MAMAD safe-room
#         W_OPENING        = 0.18   # penalty from windows / doors
#         W_DEBRIS         = 0.10   # flying glass / debris
#         W_EVACUATION     = 0.10   # evacuation time factor
#         W_ROOF           = 0.07   # roof protection
#         W_ROOM_SPECIFIC  = 0.10   # corner + room-size + reinforcement

#         for point in grid_points:
#             try:
#                 # ── 0. Outside-building check ──
#                 if house_boundary_points and not self._is_point_inside_house_boundary(point, house_boundary_points):
#                     point.safety_score = 5.0
#                     point.risk_level = RiskLevel.VERY_HIGH
#                     point.factors = {'outside_building': 1.0}
#                     point.evacuation_time = 0.0
#                     point.blast_protection = 0.0
#                     continue

#                 # ── 1. Exterior distance factor (0-100, farther = safer) ──
#                 ext_dist_m = self._calculate_exterior_distance(point, external_walls)
#                 # Normalise: 0 m → 0, ≥5 m → 100 (linear with saturation)
#                 MAX_SAFE_DIST_M = 5.0
#                 exterior_score = min(100.0, (ext_dist_m / MAX_SAFE_DIST_M) * 100.0)

#                 # ── 2. MAMAD distance bonus (0-90 from helper) ──
#                 mamad_bonus = self._calculate_mamad_distance_bonus(point, mamad_rooms)
#                 # Normalise to 0-100 scale
#                 mamad_score = min(100.0, (mamad_bonus / 90.0) * 100.0)

#                 # ── 3. Opening penalty (0-100 from helper, higher = worse) ──
#                 opening_penalty = self._calculate_opening_penalty(point, windows, doors)
#                 # Invert: high penalty → low safety contribution
#                 opening_score = 100.0 - opening_penalty

#                 # ── 4. Debris risk (0-100, higher = worse) ──
#                 debris_risk = self._calculate_debris_risk(point, windows)
#                 debris_score = 100.0 - debris_risk

#                 # ── 5. Evacuation time factor ──
#                 evac_time = self._calculate_evacuation_time(point, doors)
#                 # Normalise: 0 s → 100 (best), ≥120 s → 0 (worst)
#                 MAX_EVAC_S = 120.0
#                 evacuation_score = max(0.0, (1.0 - evac_time / MAX_EVAC_S) * 100.0)

#                 # ── 6. Roof protection (0-100 from helper) ──
#                 roof_score = roof_prot

#                 # ── 7. Room-specific factors ──
#                 room_specific_score = 50.0  # neutral default
#                 current_room = self._find_room_for_point(point, rooms)
#                 if current_room:
#                     room_size_f = self._calculate_room_size_factor(current_room)
#                     corner_f = self._calculate_corner_effect(point, rooms)
#                     assessment = self._find_assessment_for_room(current_room, safety_assessments)
#                     reinforced_f = self._calculate_reinforced_area(current_room, assessment)
#                     # Combine: room_size (0-80) + corner (0-70) + reinforced (0-35)
#                     # Normalise the mix to 0-100
#                     room_specific_score = min(100.0, room_size_f * 0.4 + corner_f * 0.3 + reinforced_f * 1.0)
#                 else:
#                     # Point not inside any room – likely hallway / transition
#                     room_specific_score = 30.0

#                 # ── Combine into final safety score (weighted sum) ──
#                 safety_score = (
#                     exterior_score      * W_EXTERIOR_DIST
#                     + mamad_score        * W_MAMAD
#                     + opening_score      * W_OPENING
#                     + debris_score       * W_DEBRIS
#                     + evacuation_score   * W_EVACUATION
#                     + roof_score         * W_ROOF
#                     + room_specific_score * W_ROOM_SPECIFIC
#                 )

#                 # Clamp to valid range
#                 safety_score = max(0.0, min(100.0, safety_score))

#                 # ── Derive risk level ──
#                 # Convert safety (higher = safer) to risk (higher = more dangerous)
#                 risk_score = 100.0 - safety_score
#                 risk_level = self._determine_risk_level_from_risk(risk_score)

#                 # ── Blast protection (structural factors) ──
#                 blast_protection = (
#                     exterior_score * 0.3
#                     + roof_score * 0.3
#                     + mamad_score * 0.2
#                     + (room_specific_score * 0.2 if current_room else 0.0)
#                 )
#                 blast_protection = max(0.0, min(100.0, blast_protection))

#                 # ── Store results ──
#                 point.safety_score = round(safety_score, 2)
#                 point.risk_level = risk_level
#                 point.evacuation_time = round(evac_time, 2)
#                 point.blast_protection = round(blast_protection, 2)
#                 point.factors = {
#                     'exterior_distance':   round(exterior_score, 2),
#                     'mamad_proximity':     round(mamad_score, 2),
#                     'opening_penalty':     round(opening_penalty, 2),
#                     'debris_risk':         round(debris_risk, 2),
#                     'evacuation':          round(evacuation_score, 2),
#                     'roof_protection':     round(roof_score, 2),
#                     'room_specific':       round(room_specific_score, 2),
#                 }

#             except Exception as e:
#                 print(f"[HEATMAP_DEBUG] ERROR calculating risk for point ({point.x}, {point.y}): {e}")
#                 import traceback
#                 print(traceback.format_exc())
#                 # Graceful fallback – mark as medium risk
#                 point.safety_score = 40.0
#                 point.risk_level = RiskLevel.MEDIUM
#                 point.factors = {'error_fallback': 1.0}
#                 point.evacuation_time = 120.0
#                 point.blast_protection = 30.0

#         # ── Post-loop debug summary ──
#         safety_vals = [p.safety_score for p in grid_points]
#         print(f"[HEATMAP_DEBUG] Multi-factor calculation complete – "
#               f"range {min(safety_vals):.1f}-{max(safety_vals):.1f}, "
#               f"avg {sum(safety_vals)/len(safety_vals):.1f}")
        
#         # Generate visualizations
#         try:
#             print(f"[HEATMAP_DEBUG] Generating visualizations for {width}x{height} grid")
#             heatmap_visualizations = self._generate_heatmap_visualizations(grid_points, width, height)
#             print(f"[HEATMAP_DEBUG] Visualizations generated successfully")
#         except Exception as e:
#             print(f"[HEATMAP_DEBUG] ERROR generating visualizations: {e}")
#             import traceback
#             print(f"[HEATMAP_DEBUG] Visualization error traceback: {traceback.format_exc()}")
#             # Create minimal fallback visualization
#             heatmap_visualizations = {
#                 'safety_heatmap': [[50.0 for _ in range(width//20)] for _ in range(height//20)],
#                 'evacuation_heatmap': [[50.0 for _ in range(width//20)] for _ in range(height//20)],
#                 'protection_heatmap': [[50.0 for _ in range(width//20)] for _ in range(height//20)],
#                 'grid_resolution': self.grid_resolution
#             }
        
#         # Identify safe and risk zones
#         safe_zones = self._identify_safe_zones(grid_points)
#         risk_zones = self._identify_risk_zones(grid_points)
        
#         # Generate recommendations
#         recommendations = self._generate_safety_recommendations(
#             grid_points, safe_zones, risk_zones, rooms
#         )
        
#         # Calculate statistics
#         statistics = self._calculate_statistics(grid_points)
        
#         # Serialize grid points for response
#         serialized_points = [self._serialize_grid_point(point) for point in grid_points]
        
#         # ---------------- Debug summary ----------------
#         if self.debug:
#             safety_vals = [p.safety_score for p in grid_points]
#             print(f"[DEBUG] Safety range {min(safety_vals):.1f}-{max(safety_vals):.1f} avg {sum(safety_vals)/len(safety_vals):.1f}")
#             outside = [p for p in grid_points if not self._find_room_for_point(p, rooms)]
#             print(f"[DEBUG] Outside grid points: {len(outside)}; sample: {[(p.x, p.y, p.safety_score) for p in outside[:10]]}")
        
#         return {
#             'heatmap_data': {
#                 'grid_points': serialized_points,
#                 'visualizations': heatmap_visualizations,
#                 'safe_zones': safe_zones,
#                 'risk_zones': risk_zones,
#                 'statistics': statistics,
#                 'recommendations': recommendations
#             },
#             'metadata': {
#                 'grid_resolution': self.grid_resolution,
#                 'total_points': len(grid_points),
#                 'floor_plan_dimensions': {'width': width, 'height': height},
#                 'mamad_rooms_count': len(mamad_rooms)
#             }
#         }

#     def _calculate_floor_plan_dimensions(self, floor_plan_data: Dict[str, Any], house_boundaries: Dict, rooms: List) -> Tuple[int, int]:
#         """Calculate floor plan dimensions from boundaries or rooms"""
#         # First priority: use image_dimensions from the payload
#         image_dimensions = floor_plan_data.get('image_dimensions', {})
#         if image_dimensions:
#             width = image_dimensions.get('width', 0)
#             height = image_dimensions.get('height', 0)
#             if width > 0 and height > 0:
#                 print(f"[HEATMAP_DEBUG] Using image dimensions: {width}x{height}")
#                 return int(width), int(height)
        
#         # Second priority: use house boundaries
#         if house_boundaries and 'exterior_perimeter' in house_boundaries:
#             perimeter = house_boundaries['exterior_perimeter']
#             max_x = max(p.get('x', 0) for p in perimeter)
#             max_y = max(p.get('y', 0) for p in perimeter)
#             print(f"[HEATMAP_DEBUG] Using house boundaries dimensions: {int(max_x)}x{int(max_y)}")
#             return int(max_x), int(max_y)
        
#         # Third priority: fall back to room boundaries
#         if rooms:
#             max_x = 0
#             max_y = 0
#             for room in rooms:
#                 boundaries = room.get('boundaries', [])
#                 if boundaries:
#                     for boundary in boundaries:
#                         max_x = max(max_x, boundary.get('x', 0))
#                         max_y = max(max_y, boundary.get('y', 0))
#             if max_x > 0 and max_y > 0:
#                 print(f"[HEATMAP_DEBUG] Using room boundaries dimensions: {int(max_x)}x{int(max_y)}")
#             return int(max_x) if max_x > 0 else 800, int(max_y) if max_y > 0 else 600
        
#         print(f"[HEATMAP_DEBUG] Using default dimensions: 800x600")
#         return 800, 600  # Default dimensions

#     def _create_safety_grid(self, width: int, height: int) -> List[GridPoint]:
#         """Create grid points for safety analysis"""
#         grid_points = []
        
#         # Ensure we cover the entire area by extending to the full dimensions
#         # Add some padding to ensure complete coverage
#         extended_width = width + self.grid_resolution
#         extended_height = height + self.grid_resolution
        
#         for y in range(0, extended_height, self.grid_resolution):
#             for x in range(0, extended_width, self.grid_resolution):
#                 point = GridPoint(
#                     x=x,
#                     y=y,
#                     safety_score=0.0,
#                     risk_level=RiskLevel.MEDIUM,
#                     factors={},
#                     evacuation_time=0.0,
#                     blast_protection=0.0
#                 )
#                 grid_points.append(point)
        
#         print(f"[HEATMAP_DEBUG] Created grid: {len(grid_points)} points covering {width}x{height} -> {extended_width}x{extended_height}")
#         print(f"[HEATMAP_DEBUG] Grid resolution: {self.grid_resolution}, expected points: {(extended_width//self.grid_resolution + 1) * (extended_height//self.grid_resolution + 1)}")
        
#         return grid_points

#     def _is_near_external_wall(self, pos, external_walls, threshold=30):
#         """Check if a position is near any external wall segment (within threshold in pixels)"""
#         for wall in external_walls:
#             start = wall.get('segment_start', {})
#             end = wall.get('segment_end', {})
#             if start and end:
#                 dist = self._point_to_line_distance(
#                     pos.get('x', 0), pos.get('y', 0),
#                     start.get('x', 0), start.get('y', 0),
#                     end.get('x', 0), end.get('y', 0)
#                 )
#                 if dist <= threshold:
#                     return True
#         return False

#     def _classify_external_openings(self, windows, doors, external_walls):
#         """Mark windows/doors as external if near an external wall"""
#         for w in windows:
#             pos = w.get('position', {})
#             w['is_external'] = self._is_near_external_wall(pos, external_walls)
#         for d in doors:
#             pos = d.get('position', {})
#             d['is_external'] = self._is_near_external_wall(pos, external_walls)

#     def _is_point_inside_house_boundary(self, point: GridPoint, house_boundary_points: List[Dict[str, float]]) -> bool:
#         """Check if a grid point is inside the house boundary polygon"""
#         if not house_boundary_points or len(house_boundary_points) < 3:
#             return False
        
#         return self._point_in_polygon(point.x, point.y, house_boundary_points)

#     def _calculate_exterior_distance(self, point: GridPoint, external_walls: List[Dict[str, Any]]) -> float:
#         """Calculate distance from exterior walls"""
#         if not external_walls:
#             return 1.0
        
#         min_distance = float('inf')
        
#         for wall in external_walls:
#             start = wall.get('segment_start', {})
#             end = wall.get('segment_end', {})
            
#             if start and end:
#                 distance = self._point_to_line_distance(
#                     point.x, point.y,
#                     start.get('x', 0), start.get('y', 0),
#                     end.get('x', 0), end.get('y', 0)
#                 )
#                 min_distance = min(min_distance, distance)
        
#         return max(0, min_distance * self.pixel_to_meter_ratio)

#     def _calculate_evacuation_time(self, point: GridPoint, doors: List[Dict[str, Any]]) -> float:
#         """Calculate estimated evacuation time from this point"""
#         exits = [d for d in doors if d.get('is_external', False) or d.get('leads_to_exit', False)]
        
#         if not exits:
#             return 300.0
        
#         min_distance = float('inf')
        
#         for exit_door in exits:
#             exit_pos = exit_door.get('position', {})
#             exit_x = exit_pos.get('x', 0)
#             exit_y = exit_pos.get('y', 0)
            
#             distance = math.sqrt((point.x - exit_x)**2 + (point.y - exit_y)**2)
#             min_distance = min(min_distance, distance)
        
#         distance_meters = min_distance * self.pixel_to_meter_ratio
#         evacuation_time = distance_meters / 1.0
#         route_complexity_penalty = min(30, distance_meters * 0.2)
        
#         return evacuation_time + route_complexity_penalty

#     def _generate_heatmap_visualizations(self, grid_points: List[GridPoint], width: int, height: int) -> Dict[str, Any]:
#         """Generate heatmap visualization data"""
#         grid_width = width // self.grid_resolution + 1
#         grid_height = height // self.grid_resolution + 1
        
#         safety_matrix = np.zeros((grid_height, grid_width))
#         evacuation_matrix = np.zeros((grid_height, grid_width))
#         protection_matrix = np.zeros((grid_height, grid_width))
        
#         for point in grid_points:
#             grid_x = min(point.x // self.grid_resolution, grid_width - 1)
#             grid_y = min(point.y // self.grid_resolution, grid_height - 1)
            
#             safety_matrix[grid_y, grid_x] = point.safety_score
#             evacuation_matrix[grid_y, grid_x] = max(0, 300 - point.evacuation_time)
#             protection_matrix[grid_y, grid_x] = point.blast_protection
        
#         # Apply smoothing
#         safety_matrix = gaussian_filter(safety_matrix, sigma=1)
#         evacuation_matrix = gaussian_filter(evacuation_matrix, sigma=1)
#         protection_matrix = gaussian_filter(protection_matrix, sigma=1)
        
#         return {
#             'safety_heatmap': safety_matrix.tolist(),
#             'evacuation_heatmap': evacuation_matrix.tolist(),
#             'protection_heatmap': protection_matrix.tolist(),
#             'grid_resolution': self.grid_resolution
#         }

#     def _identify_safe_zones(self, grid_points: List[GridPoint]) -> List[Dict[str, Any]]:
#         """Identify areas with high safety scores"""
#         safe_zones = []
#         high_safety_points = [p for p in grid_points if p.safety_score >= 70]
        
#         if not high_safety_points:
#             return safe_zones
        
#         zones = []
#         for point in high_safety_points:
#             added_to_zone = False
            
#             for zone in zones:
#                 for zone_point in zone:
#                     distance = math.sqrt((point.x - zone_point.x)**2 + (point.y - zone_point.y)**2)
#                     if distance <= self.grid_resolution * 1.5:
#                         zone.append(point)
#                         added_to_zone = True
#                         break
                
#                 if added_to_zone:
#                     break
            
#             if not added_to_zone:
#                 zones.append([point])
        
#         for i, zone in enumerate(zones):
#             if len(zone) >= 4:
#                 avg_safety = sum(p.safety_score for p in zone) / len(zone)
#                 center_x = sum(p.x for p in zone) / len(zone)
#                 center_y = sum(p.y for p in zone) / len(zone)
                
#                 safe_zones.append({
#                     'zone_id': f'safe_zone_{i}',
#                     'center': {'x': center_x, 'y': center_y},
#                     'average_safety_score': avg_safety,
#                     'area_points': len(zone),
#                     'estimated_capacity': len(zone) * 2,
#                     'points': [{'x': p.x, 'y': p.y, 'score': p.safety_score} for p in zone]
#                 })
        
#         return safe_zones

#     def _identify_risk_zones(self, grid_points: List[GridPoint]) -> List[Dict[str, Any]]:
#         """Identify areas with low safety scores"""
#         risk_zones = []
#         low_safety_points = [p for p in grid_points if p.safety_score <= 30]
        
#         if not low_safety_points:
#             return risk_zones
        
#         zones = []
#         for point in low_safety_points:
#             added_to_zone = False
            
#             for zone in zones:
#                 for zone_point in zone:
#                     distance = math.sqrt((point.x - zone_point.x)**2 + (point.y - zone_point.y)**2)
#                     if distance <= self.grid_resolution * 1.5:
#                         zone.append(point)
#                         added_to_zone = True
#                         break
                
#                 if added_to_zone:
#                     break
            
#             if not added_to_zone:
#                 zones.append([point])
        
#         for i, zone in enumerate(zones):
#             if len(zone) >= 4:
#                 avg_safety = sum(p.safety_score for p in zone) / len(zone)
#                 center_x = sum(p.x for p in zone) / len(zone)
#                 center_y = sum(p.y for p in zone) / len(zone)
                
#                 risk_zones.append({
#                     'zone_id': f'risk_zone_{i}',
#                     'center': {'x': center_x, 'y': center_y},
#                     'average_safety_score': avg_safety,
#                     'area_points': len(zone),
#                     'warning_level': 'high' if avg_safety < 20 else 'medium',
#                     'points': [{'x': p.x, 'y': p.y, 'score': p.safety_score} for p in zone]
#                 })
        
#         return risk_zones

#     def _generate_safety_recommendations(
#         self, 
#         grid_points: List[GridPoint], 
#         safe_zones: List[Dict[str, Any]], 
#         risk_zones: List[Dict[str, Any]], 
#         rooms: List[Dict[str, Any]]
#     ) -> List[Dict[str, str]]:
#         """Generate safety recommendations based on heatmap analysis"""
#         recommendations = []
        
#         if safe_zones:
#             best_safe_zone = max(safe_zones, key=lambda z: z['average_safety_score'])
#             recommendations.append({
#                 'type': 'safe_zone',
#                 'priority': 'high',
#                 'title': 'Primary Safe Zone Identified',
#                 'description': f'The safest area is at coordinates ({best_safe_zone["center"]["x"]:.0f}, {best_safe_zone["center"]["y"]:.0f}) with safety score {best_safe_zone["average_safety_score"]:.1f}',
#                 'action': 'Designate this area as primary emergency shelter location'
#             })
        
#         if risk_zones:
#             worst_risk_zone = min(risk_zones, key=lambda z: z['average_safety_score'])
#             recommendations.append({
#                 'type': 'risk_zone',
#                 'priority': 'critical',
#                 'title': 'High Risk Area Identified',
#                 'description': f'Dangerous area at coordinates ({worst_risk_zone["center"]["x"]:.0f}, {worst_risk_zone["center"]["y"]:.0f}) with safety score {worst_risk_zone["average_safety_score"]:.1f}',
#                 'action': 'Avoid this area during emergencies, consider structural improvements'
#             })
        
#         avg_evacuation_time = sum(p.evacuation_time for p in grid_points) / len(grid_points)
#         if avg_evacuation_time > 120:
#             recommendations.append({
#                 'type': 'evacuation',
#                 'priority': 'high',
#                 'title': 'Evacuation Routes Need Improvement',
#                 'description': f'Average evacuation time is {avg_evacuation_time:.1f} seconds',
#                 'action': 'Consider adding additional exits or improving pathway accessibility'
#             })
        
#         mamad_rooms = [r for r in rooms if r.get('is_mamad', False) or 'mamad' in r.get('type', '').lower()]
#         if not mamad_rooms:
#             recommendations.append({
#                 'type': 'mamad',
#                 'priority': 'high',
#                 'title': 'No Mamad (Safe Room) Detected',
#                 'description': 'No reinforced safe room found in floor plan',
#                 'action': 'Consider designating or constructing a Mamad for optimal protection'
#             })
        
#         return recommendations

#     def _calculate_statistics(self, grid_points: List[GridPoint]) -> Dict[str, Any]:
#         """Calculate overall statistics for the heatmap"""
#         safety_scores = [p.safety_score for p in grid_points]
#         evacuation_times = [p.evacuation_time for p in grid_points]
        
#         return {
#             'total_grid_points': len(grid_points),
#             'average_safety_score': sum(safety_scores) / len(safety_scores),
#             'min_safety_score': min(safety_scores),
#             'max_safety_score': max(safety_scores),
#             'average_evacuation_time': sum(evacuation_times) / len(evacuation_times),
#             'safe_points_count': len([p for p in grid_points if p.safety_score >= 70]),
#             'risk_points_count': len([p for p in grid_points if p.safety_score <= 30]),
#             'coverage_area_m2': len(grid_points) * (self.grid_resolution * self.pixel_to_meter_ratio) ** 2
#         }

#     # Helper methods
#     def _find_room_for_point(self, point: GridPoint, rooms: List[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
#         """Find which room contains the given point"""
#         if not rooms:
#             return None
            
#         for room in rooms:
#             boundaries = room.get('boundaries', [])
#             if not boundaries:
#                 # Room has no boundaries, skip it
#                 continue
#             if not isinstance(boundaries, list) or len(boundaries) < 3:
#                 # Invalid boundary format
#                 continue
#             if self._point_in_polygon(point.x, point.y, boundaries):
#                 return room
#         return None

#     def _find_assessment_for_room(self, room: Dict[str, Any], assessments: List[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
#         """Find safety assessment for a specific room"""
#         if not room or not assessments:
#             return None
        
#         room_id = room.get('id', room.get('room_id', ''))
        
#         for assessment in assessments:
#             if assessment.get('room_id') == room_id:
#                 return assessment
        
#         return None

#     def _point_in_polygon(self, x: float, y: float, polygon: List[Dict[str, float]]) -> bool:
#         """Check if point is inside polygon using ray casting algorithm"""
#         if len(polygon) < 3:
#             return False
        
#         inside = False
#         j = len(polygon) - 1
        
#         for i in range(len(polygon)):
#             xi, yi = polygon[i].get('x', 0), polygon[i].get('y', 0)
#             xj, yj = polygon[j].get('x', 0), polygon[j].get('y', 0)
            
#             if ((yi > y) != (yj > y)) and (x < (xj - xi) * (y - yi) / (yj - yi) + xi):
#                 inside = not inside
#             j = i
        
#         return inside

#     def _point_to_line_distance(self, px: float, py: float, x1: float, y1: float, x2: float, y2: float) -> float:
#         """Calculate distance from point to line segment"""
#         A = px - x1
#         B = py - y1
#         C = x2 - x1
#         D = y2 - y1
        
#         dot = A * C + B * D
#         len_sq = C * C + D * D
        
#         if len_sq == 0:
#             return math.sqrt(A * A + B * B)
        
#         param = dot / len_sq
        
#         if param < 0:
#             xx, yy = x1, y1
#         elif param > 1:
#             xx, yy = x2, y2
#         else:
#             xx = x1 + param * C
#             yy = y1 + param * D
        
#         dx = px - xx
#         dy = py - yy
#         return math.sqrt(dx * dx + dy * dy)

#     def _calculate_room_size_factor(self, room: Dict[str, Any]) -> float:
#         """Calculate room size factor for safety"""
#         if not room:
#             return 50.0
        
#         area = room.get('area_m2', 0)
        
#         if 10 <= area <= 20:
#             return 80.0
#         elif 5 <= area < 10 or 20 < area <= 30:
#             return 60.0
#         elif area < 5:
#             return 30.0
#         else:
#             return 40.0

#     def _calculate_reinforced_area(self, room: Dict[str, Any], assessment: Dict[str, Any]) -> float:
#         """Calculate reinforced area bonus"""
#         if not room or not assessment:
#             return 0.0
        
#         responses = assessment.get('responses', {})
#         reinforcement_score = 0.0
        
#         if responses.get('wall_material', '').lower() in ['concrete', 'steel']:
#             reinforcement_score += 20
        
#         if 'thick' in responses.get('wall_thickness', '').lower():
#             reinforcement_score += 15
        
#         return reinforcement_score

#     def _calculate_corner_effect(self, point: GridPoint, rooms: List[Dict[str, Any]]) -> float:
#         """Calculate corner protection effect"""
#         current_room = self._find_room_for_point(point, rooms)
        
#         if not current_room:
#             return 0.0
        
#         boundaries = current_room.get('boundaries', [])
#         if len(boundaries) < 3:
#             return 0.0
        
#         min_corner_distance = float('inf')
        
#         for boundary in boundaries:
#             corner_x = boundary.get('x', 0)
#             corner_y = boundary.get('y', 0)
#             distance = math.sqrt((point.x - corner_x)**2 + (point.y - corner_y)**2)
#             min_corner_distance = min(min_corner_distance, distance)
        
#         if min_corner_distance < 50:
#             return 70 * (1 - min_corner_distance / 50)
        
#         return 0.0

#     def _calculate_evacuation_distance(self, point: GridPoint, doors: List[Dict[str, Any]]) -> float:
#         """Calculate evacuation route distance"""
#         exits = [d for d in doors if d.get('is_external', False) or d.get('leads_to_exit', False)]
        
#         if not exits:
#             return 100.0
        
#         min_distance = float('inf')
        
#         for exit_door in exits:
#             exit_pos = exit_door.get('position', {})
#             exit_x = exit_pos.get('x', 0)
#             exit_y = exit_pos.get('y', 0)
            
#             distance = math.sqrt((point.x - exit_x)**2 + (point.y - exit_y)**2)
#             min_distance = min(min_distance, distance)
        
#         return min_distance * self.pixel_to_meter_ratio

#     def _calculate_exit_access(self, point: GridPoint, doors: List[Dict[str, Any]]) -> float:
#         """Calculate emergency exit access score"""
#         exits = [d for d in doors if d.get('is_external', False) or d.get('leads_to_exit', False)]
        
#         if not exits:
#             return 0.0
        
#         if len(exits) >= 2:
#             return 80.0
#         elif len(exits) == 1:
#             return 50.0
#         else:
#             return 0.0

#     def _calculate_debris_risk(self, point: GridPoint, windows: List[Dict[str, Any]]) -> float:
#         """Calculate debris risk from windows"""
#         debris_risk = 0.0
        
#         for window in windows:
#             window_pos = window.get('position', {})
#             window_x = window_pos.get('x', 0)
#             window_y = window_pos.get('y', 0)
            
#             distance = math.sqrt((point.x - window_x)**2 + (point.y - window_y)**2)
            
#             if distance < 100:
#                 size_factor = {
#                     'small': 1.0,
#                     'medium': 1.5,
#                     'large': 2.0,
#                     'floor_to_ceiling': 3.0
#                 }.get(window.get('size_category', 'medium'), 1.5)
                
#                 proximity_factor = max(0, 100 - distance) / 100
#                 debris_risk += size_factor * proximity_factor * 10
        
#         return min(100, debris_risk)

#     def _glazing_resistance(self, glazing_type: str) -> float:
#         """Return mapped glazing/door resistance factor in range 0-1"""
#         if not glazing_type:
#             glazing_type = 'unknown'
#         return self.glazing_resistance.get(glazing_type.lower(), self.glazing_resistance['unknown'])

#     def _calculate_opening_penalty(
#         self,
#         point: GridPoint,
#         windows: List[Dict[str, Any]],
#         doors: List[Dict[str, Any]]
#     ) -> float:
#         """Aggregate penalty (0-100) for proximity to weak openings"""
#         penalty = 0.0

#         # Windows – larger base penalty
#         for w in windows:
#             pos = w.get('position', {})
#             d = self._euclidean_distance(point.x, point.y, pos.get('x', 0), pos.get('y', 0))
#             if d < 120:  # 6 m radius
#                 base = 60  # max penalty from a single window
#                 R = self._glazing_resistance(w.get('glazing_type', 'ordinary'))
#                 penalty += (1 - R) * (120 - d) / 120 * base

#         # Doors – lower base penalty (wood/metal)
#         for d_open in doors:
#             pos = d_open.get('position', {})
#             d = self._euclidean_distance(point.x, point.y, pos.get('x', 0), pos.get('y', 0))
#             if d < 120:
#                 base = 40
#                 material_res = self._glazing_resistance(d_open.get('door_grade', 'ordinary'))
#                 penalty += (1 - material_res) * (120 - d) / 120 * base

#         return min(100.0, penalty)

#     def _euclidean_distance(self, x1: float, y1: float, x2: float, y2: float) -> float:
#         return math.hypot(x1 - x2, y1 - y2)

#     def _calculate_mamad_distance_bonus(
#         self,
#         point: GridPoint,
#         mamad_rooms: List[Dict[str, Any]]
#     ) -> float:
#         """Exponential decay bonus based on distance to nearest MAMAD wall"""
#         if not mamad_rooms:
#             return 0.0

#         min_d = float('inf')
#         for room in mamad_rooms:
#             boundaries = room.get('boundaries') or room.get('boundary') or {}
#             # Support both list of points or dict with 'points'
#             polygon = []
#             if isinstance(boundaries, list):
#                 polygon = boundaries
#             elif isinstance(boundaries, dict):
#                 polygon = boundaries.get('points', [])
#             d = self._point_to_polygon_distance(point.x, point.y, polygon)
#             min_d = min(min_d, d)

#         # Grid resolution ≈ 0.05 m/px (from elsewhere) → decay length 70 px ≈ 3.5 m
#         bonus = 90 * math.exp(-min_d / 70) if min_d != float('inf') else 0.0
#         return bonus

#     def _point_to_polygon_distance(self, x: float, y: float, polygon: List[Dict[str, float]]) -> float:
#         """Approximate min distance from a point to polygon vertices"""
#         if not polygon:
#             return float('inf')
#         return min(self._euclidean_distance(x, y, p.get('x', 0), p.get('y', 0)) for p in polygon)

#     def _calculate_roof_protection(self, assessment: Dict[str, Any]) -> float:
#         """Map roof material/thickness to protection (0-100)"""
#         if not assessment:
#             return 50.0

#         responses = assessment.get('responses', {})
#         material = responses.get('roof_material', 'concrete').lower()
#         thickness = responses.get('roof_thickness', '20cm').lower()

#         material_values = {
#             'reinforced_concrete': 90,
#             'concrete': 80,
#             'hollow_block': 60,
#             'steel': 70,
#             'wood': 30,
#             'unknown': 50
#         }

#         base = material_values.get(material, 50)

#         try:
#             num_cm = float(''.join(filter(str.isdigit, thickness)))
#             if num_cm >= 25:
#                 base += 10
#             elif num_cm <= 10:
#                 base -= 10
#         except Exception:
#             pass

#         return max(0.0, min(100.0, base))

#     def _serialize_grid_point(self, point: GridPoint) -> Dict[str, Any]:
#         """Convert GridPoint to serializable dictionary"""
#         return {
#             'x': point.x,
#             'y': point.y,
#             'safety_score': round(point.safety_score, 1),
#             'risk_level': point.risk_level.name,
#             'factors': {k: round(v, 2) for k, v in point.factors.items()},
#             'evacuation_time': round(point.evacuation_time, 1),
#             'blast_protection': round(point.blast_protection, 1)
#         }

#     # ------------------------------------------------------------------
#     # NEW helper – distance from a point to the nearest edge of polygon
#     # ------------------------------------------------------------------
#     def _point_to_polygon_edge_distance(self, x: float, y: float, polygon: List[Dict[str, float]]) -> float:
#         """Return minimum distance (pixels) from the point (x,y) to any edge of the polygon."""
#         if not polygon or len(polygon) < 2:
#             return float('inf')

#         min_dist = float('inf')
#         n = len(polygon)
#         for i in range(n):
#             p1 = polygon[i]
#             p2 = polygon[(i + 1) % n]
#             d = self._point_to_line_distance(
#                 x, y,
#                 p1.get('x', 0), p1.get('y', 0),
#                 p2.get('x', 0), p2.get('y', 0)
#             )
#             min_dist = min(min_dist, d)
#         return min_dist

#     # ------------------------------------------------------------------
#     # Simple helper – map numeric RISK score to categorical RiskLevel
#     # ------------------------------------------------------------------
#     def _determine_risk_level_from_risk(self, risk_score: float) -> RiskLevel:
#         """Return RiskLevel based on *risk* score (0-100, higher = more risky)."""
#         if risk_score >= 80:
#             return RiskLevel.VERY_HIGH
#         elif risk_score >= 65:
#             return RiskLevel.HIGH
#         elif risk_score >= 45:
#             return RiskLevel.MEDIUM
#         elif risk_score >= 25:
#             return RiskLevel.LOW
#         else:
#             return RiskLevel.VERY_LOW

#!/usr/bin/env python3
"""
Explosive Risk Heatmap Service
Generates safety heatmaps for floor plans based on explosive attack risk assessment
"""

import numpy as np
import math
from typing import Dict, List, Tuple, Any, Optional
from dataclasses import dataclass
from enum import Enum
from PIL import Image
from datetime import datetime

try:
    from scipy.spatial.distance import cdist
    from scipy.ndimage import gaussian_filter
except ImportError:
    # Fallback implementations if scipy is not available
    def gaussian_filter(matrix, sigma=1):
        return matrix
    
    def cdist(XA, XB):
        return np.array([[np.linalg.norm(np.array(a) - np.array(b)) for b in XB] for a in XA])

class RiskLevel(Enum):
    VERY_LOW = 1
    LOW = 2
    MEDIUM = 3
    HIGH = 4
    VERY_HIGH = 5

@dataclass
class GridPoint:
    x: int
    y: int
    safety_score: float
    risk_level: RiskLevel
    factors: Dict[str, float]
    evacuation_time: float
    blast_protection: float

@dataclass
class ExplosiveRiskFactors:
    """Factors that affect explosive attack risk and safety"""
    
    # Structural Protection
    wall_material_protection: float = 0.0
    wall_thickness_protection: float = 0.0
    ceiling_protection: float = 0.0
    floor_material: float = 0.0
    
    # Blast Wave Factors
    distance_from_exterior: float = 0.0
    distance_from_windows: float = 0.0
    distance_from_doors: float = 0.0
    corner_effect: float = 0.0
    
    # Evacuation Factors
    evacuation_route_distance: float = 0.0
    evacuation_route_obstacles: float = 0.0
    emergency_exit_access: float = 0.0
    
    # Environmental Factors
    room_size_factor: float = 0.0
    ventilation_factor: float = 0.0
    debris_risk: float = 0.0
    
    # Special Considerations
    mamad_protection: float = 0.0
    reinforced_area: float = 0.0
    critical_infrastructure: float = 0.0
    # New – Openings & additional protections
    opening_penalty: float = 0.0
    mamad_distance_bonus: float = 0.0
    roof_protection: float = 0.0

class ExplosiveRiskHeatmapService:
    def __init__(self):
        self.grid_resolution = 15  # Grid cell size in pixels (reduced for better coverage)
        self.blast_radius_meters = 50  # Effective blast radius in meters
        self.pixel_to_meter_ratio = 0.1  # Default: 10 pixels = 1 meter
        
        # Material protection factors (0-1, higher = better protection)
        self.material_protection_values = {
            'concrete': 0.85,
            'reinforced_concrete': 0.95,
            'brick': 0.70,
            'stone': 0.75,
            'wood': 0.30,
            'drywall': 0.20,
            'glass': 0.05,
            'metal': 0.60,
            'unknown': 0.40
        }
        
        # Wall thickness protection (cm to protection factor)
        self.thickness_protection_values = {
            'very_thick': 0.70,  # >30cm - reduced from 0.90
            'thick': 0.55,       # 20-30cm - reduced from 0.75
            'medium': 0.35,      # 10-20cm - reduced from 0.50
            'thin': 0.15,        # <10cm - reduced from 0.25
            'unknown': 0.25      # reduced from 0.40
        }

        # Glazing resistance factors (0-1, higher = better blast resistance)
        self.glazing_resistance = {
            'ordinary': 0.10,
            'single_glazed': 0.15,
            'double_glazed': 0.25,
            'laminated': 0.40,
            'blast': 0.70,
            'unknown': 0.10
        }

        # Debug flag – verbose stats printed when True
        self.debug = True

    async def generate_heatmap(self, floor_plan_data: dict, analysis_id: str = None) -> dict:
        """Generate explosive risk heatmap for floor plan"""
        try:
            print(f"[HEATMAP_DEBUG] Starting heatmap generation")
            print(f"[HEATMAP_DEBUG] analysis_id: {analysis_id}")
            print(f"[HEATMAP_DEBUG] floor_plan_data keys: {list(floor_plan_data.keys()) if floor_plan_data else 'None'}")
            
            # For compatibility mode, use the existing generate_explosive_risk_heatmap method
            if not analysis_id:
                print(f"[HEATMAP_DEBUG] No analysis_id, using compatibility mode")
                print(f"[HEATMAP_DEBUG] Using compatibility mode for heatmap generation")
                try:
                    result = self.generate_explosive_risk_heatmap(floor_plan_data)
                    print(f"[HEATMAP_DEBUG] ✅ Compatibility mode heatmap generation completed")
                    return result
                except Exception as e:
                    print(f"[HEATMAP_DEBUG] ERROR in compatibility mode: {e}")
                    import traceback
                    print(f"[HEATMAP_DEBUG] Full traceback: {traceback.format_exc()}")
                    raise
            
            # For structured mode with analysis_id, get structured data
            print(f"[HEATMAP_DEBUG] Using structured mode with analysis_id: {analysis_id}")
            try:
                # This would call the structured safety service
                # For now, fall back to compatibility mode
                print(f"[HEATMAP_DEBUG] Structured mode not fully implemented, falling back to compatibility")
                result = self.generate_explosive_risk_heatmap(floor_plan_data)
                return result
            except Exception as e:
                print(f"[HEATMAP_DEBUG] ERROR in structured mode: {e}")
                import traceback
                print(f"[HEATMAP_DEBUG] Full traceback: {traceback.format_exc()}")
                raise
            
        except Exception as e:
            print(f"[HEATMAP_DEBUG] ❌ FATAL ERROR in heatmap generation: {e}")
            import traceback
            print(f"[HEATMAP_DEBUG] Full traceback: {traceback.format_exc()}")
            raise Exception(f"Error generating heatmap:\n{e}")

    def _convert_legacy_data(self, floor_plan_data: dict) -> dict:
        """Convert legacy floor plan data to assessment format"""
        print(f"[HEATMAP_DEBUG] Converting legacy data...")
        print(f"[HEATMAP_DEBUG] Input floor_plan_data: {floor_plan_data}")
        
        try:
            # Extract rooms data
            rooms = floor_plan_data.get('rooms', [])
            print(f"[HEATMAP_DEBUG] Found {len(rooms)} rooms")
            
            # Convert to assessment format
            assessment_data = {
                'rooms': [],
                'building_info': floor_plan_data.get('building_info', {}),
                'safety_features': floor_plan_data.get('safety_features', {})
            }
            
            for i, room in enumerate(rooms):
                print(f"[HEATMAP_DEBUG] Processing room {i}: {room.get('name', 'Unknown')}")
                
                # Convert room to assessment format
                room_assessment = {
                    'name': room.get('name', f'Room {i+1}'),
                    'type': room.get('type', 'unknown'),
                    'area': room.get('area', 0),
                    'coordinates': room.get('coordinates', []),
                    'safety_score': room.get('safety_score', 0.5),  # Default moderate safety
                    'risk_factors': room.get('risk_factors', []),
                    'safety_features': room.get('safety_features', [])
                }
                
                assessment_data['rooms'].append(room_assessment)
                print(f"[HEATMAP_DEBUG] Converted room: {room_assessment['name']} (safety_score: {room_assessment['safety_score']})")
            
            print(f"[HEATMAP_DEBUG] ✅ Legacy data conversion completed")
            print(f"[HEATMAP_DEBUG] Final assessment_data keys: {list(assessment_data.keys())}")
            return assessment_data
            
        except Exception as e:
            print(f"[HEATMAP_DEBUG] ERROR in legacy data conversion: {e}")
            import traceback
            print(f"[HEATMAP_DEBUG] Full traceback: {traceback.format_exc()}")
            raise

    def _convert_house_boundary_to_external_walls(self, house_boundary_points: List[Dict[str, float]]) -> List[Dict[str, Any]]:
        """Convert house boundary polygon points to external wall segments"""
        if not house_boundary_points or len(house_boundary_points) < 3:
            print(f"[HEATMAP_DEBUG] Invalid house boundary points: {house_boundary_points}")
            return []
        
        external_walls = []
        
        # Convert polygon points to wall segments
        for i in range(len(house_boundary_points)):
            current_point = house_boundary_points[i]
            next_point = house_boundary_points[(i + 1) % len(house_boundary_points)]
            
            wall_segment = {
                'segment_start': {
                    'x': current_point.get('x', 0),
                    'y': current_point.get('y', 0)
                },
                'segment_end': {
                    'x': next_point.get('x', 0),
                    'y': next_point.get('y', 0)
                }
            }
            external_walls.append(wall_segment)
        
        print(f"[HEATMAP_DEBUG] Converted {len(house_boundary_points)} boundary points to {len(external_walls)} external wall segments")
        if external_walls:
            print(f"[HEATMAP_DEBUG] First wall segment: {external_walls[0]}")
        
        return external_walls

    def generate_explosive_risk_heatmap(
        self, 
        floor_plan_data: Dict[str, Any]
    ) -> Dict[str, Any]:
        """
        Generate comprehensive explosive risk heatmap
        
        Args:
            floor_plan_data: Complete floor plan data with all required fields
            
        Returns:
            Dictionary containing heatmap data, grid points, and analysis
        """
        
        print(f"[HEATMAP_DEBUG] generate_explosive_risk_heatmap called")
        print(f"[HEATMAP_DEBUG] floor_plan_data keys: {list(floor_plan_data.keys())}")
        
        # Extract dimensions from floor plan data
        house_boundaries = floor_plan_data.get('house_boundaries', {})
        rooms = floor_plan_data.get('rooms', [])
        external_walls = floor_plan_data.get('external_walls', [])
        windows = floor_plan_data.get('windows', [])
        doors = floor_plan_data.get('doors', [])
        safety_assessments = floor_plan_data.get('safety_assessments', [])
        
        # Convert house boundary points to external walls if not already provided
        if not external_walls and house_boundaries:
            house_boundary_points = house_boundaries.get('points') or house_boundaries.get('exterior_perimeter', [])
            if house_boundary_points:
                print(f"[HEATMAP_DEBUG] Converting house boundary points to external walls")
                print(f"[HEATMAP_DEBUG] House boundary points: {len(house_boundary_points)} points")
                if house_boundary_points:
                    print(f"[HEATMAP_DEBUG] First 3 boundary points: {house_boundary_points[:3]}")
                external_walls = self._convert_house_boundary_to_external_walls(house_boundary_points)
            else:
                print(f"[HEATMAP_DEBUG] No house boundary points found in house_boundaries: {house_boundaries}")
        else:
            print(f"[HEATMAP_DEBUG] External walls already provided: {len(external_walls)} segments")
        
        print(f"[HEATMAP_DEBUG] Extracted data:")
        print(f"   house_boundaries: {bool(house_boundaries)}")
        print(f"   rooms: {len(rooms)}")
        print(f"   external_walls: {len(external_walls)}")
        print(f"   windows: {len(windows)}")
        print(f"   doors: {len(doors)}")
        print(f"   safety_assessments: {len(safety_assessments)}")
        
        # Debug external walls received
        if self.debug:
            print(f"[DEBUG] External walls received: {len(external_walls)} segments")
            if external_walls:
                print(f"[DEBUG] First external wall: {external_walls[0]}")
        
        # Debug logging for MAMAD rooms
        print(f"🔥 Heatmap generation - Total rooms received: {len(rooms)}")
        mamad_rooms = [r for r in rooms if r.get('is_mamad', False) or 'mamad' in r.get('type', '').lower()]
        print(f"🔒 MAMAD rooms received: {len(mamad_rooms)}")
        for mamad_room in mamad_rooms:
            print(f"   MAMAD: {mamad_room.get('name', 'Unknown')} (Type: {mamad_room.get('type', 'Unknown')})")
        
        # Calculate floor plan dimensions
        try:
            width, height = self._calculate_floor_plan_dimensions(floor_plan_data, house_boundaries, rooms)
            print(f"[HEATMAP_DEBUG] Floor plan dimensions: {width}x{height}")
        except Exception as e:
            print(f"[HEATMAP_DEBUG] ERROR calculating dimensions: {e}")
            import traceback
            print(f"[HEATMAP_DEBUG] Full traceback: {traceback.format_exc()}")
            raise
        
        # Create grid points
        try:
            grid_points = self._create_safety_grid(width, height)
            print(f"[HEATMAP_DEBUG] Created {len(grid_points)} grid points")
        except Exception as e:
            print(f"[HEATMAP_DEBUG] ERROR creating grid points: {e}")
            import traceback
            print(f"[HEATMAP_DEBUG] Full traceback: {traceback.format_exc()}")
            raise
        
        # Before grid-point loop:
        self._classify_external_openings(windows, doors, external_walls)

        # --- MULTI-FACTOR RISK CALCULATION ---
        print(f"[HEATMAP_DEBUG] Starting multi-factor risk calculation for {len(grid_points)} points")

        # Pre-compute house boundary polygon for inside/outside checks
        house_boundary_points = []
        if house_boundaries:
            house_boundary_points = (
                house_boundaries.get('points')
                or house_boundaries.get('exterior_perimeter', [])
            )

        # Pre-compute roof protection once (building-level, not per-point)
        # Use first matching assessment or fall back to default
        roof_prot = 50.0
        if safety_assessments:
            roof_prot = self._calculate_roof_protection(safety_assessments[0])
        elif rooms:
            roof_prot = self._calculate_roof_protection({})

        # ── Factor weights ──
        # These weights control how much each factor contributes to the
        # final safety score.  They were tuned so that:
        #   • Interior distance is the strongest differentiator
        #   • MAMAD proximity provides a large, localised bonus
        #   • Openings and debris are significant penalties
        #   • Evacuation, roof, and room-specific effects provide nuance
        W_EXTERIOR_DIST  = 0.25   # distance from exterior walls
        W_MAMAD          = 0.20   # proximity to MAMAD safe-room
        W_OPENING        = 0.18   # penalty from windows / doors
        W_DEBRIS         = 0.10   # flying glass / debris
        W_EVACUATION     = 0.10   # evacuation time factor
        W_ROOF           = 0.07   # roof protection
        W_ROOM_SPECIFIC  = 0.10   # corner + room-size + reinforcement

        for point in grid_points:
            try:
                # ── 0. Outside-building check ──
                if house_boundary_points and not self._is_point_inside_house_boundary(point, house_boundary_points):
                    point.safety_score = 5.0
                    point.risk_level = RiskLevel.VERY_HIGH
                    point.factors = {'outside_building': 1.0}
                    point.evacuation_time = 0.0
                    point.blast_protection = 0.0
                    continue

                # ── 1. Exterior distance factor (0-100, farther = safer) ──
                ext_dist_m = self._calculate_exterior_distance(point, external_walls)
                # Normalise: 0 m → 0, ≥5 m → 100 (linear with saturation)
                MAX_SAFE_DIST_M = 5.0
                exterior_score = min(100.0, (ext_dist_m / MAX_SAFE_DIST_M) * 100.0)

                # ── 2. MAMAD distance bonus (0-90 from helper) ──
                mamad_bonus = self._calculate_mamad_distance_bonus(point, mamad_rooms)
                # Normalise to 0-100 scale
                mamad_score = min(100.0, (mamad_bonus / 90.0) * 100.0)

                # ── 3. Opening penalty (0-100 from helper, higher = worse) ──
                opening_penalty = self._calculate_opening_penalty(point, windows, doors)
                # Invert: high penalty → low safety contribution
                opening_score = 100.0 - opening_penalty

                # ── 4. Debris risk (0-100, higher = worse) ──
                debris_risk = self._calculate_debris_risk(point, windows)
                debris_score = 100.0 - debris_risk

                # ── 5. Evacuation time factor ──
                evac_time = self._calculate_evacuation_time(point, doors)
                # Normalise: 0 s → 100 (best), ≥120 s → 0 (worst)
                MAX_EVAC_S = 120.0
                evacuation_score = max(0.0, (1.0 - evac_time / MAX_EVAC_S) * 100.0)

                # ── 6. Roof protection (0-100 from helper) ──
                roof_score = roof_prot

                # ── 7. Room-specific factors ──
                room_specific_score = 50.0  # neutral default
                current_room = self._find_room_for_point(point, rooms)
                if current_room:
                    room_size_f = self._calculate_room_size_factor(current_room)
                    corner_f = self._calculate_corner_effect(point, rooms)
                    assessment = self._find_assessment_for_room(current_room, safety_assessments)
                    reinforced_f = self._calculate_reinforced_area(current_room, assessment)
                    # Combine: room_size (0-80) + corner (0-70) + reinforced (0-35)
                    # Normalise the mix to 0-100
                    room_specific_score = min(100.0, room_size_f * 0.4 + corner_f * 0.3 + reinforced_f * 1.0)
                else:
                    # Point not inside any room – likely hallway / transition
                    room_specific_score = 30.0

                # ── Combine into final safety score (weighted sum) ──
                safety_score = (
                    exterior_score      * W_EXTERIOR_DIST
                    + mamad_score        * W_MAMAD
                    + opening_score      * W_OPENING
                    + debris_score       * W_DEBRIS
                    + evacuation_score   * W_EVACUATION
                    + roof_score         * W_ROOF
                    + room_specific_score * W_ROOM_SPECIFIC
                )

                # Clamp to valid range
                safety_score = max(0.0, min(100.0, safety_score))

                # ── Derive risk level ──
                # Convert safety (higher = safer) to risk (higher = more dangerous)
                risk_score = 100.0 - safety_score
                risk_level = self._determine_risk_level_from_risk(risk_score)

                # ── Blast protection (structural factors) ──
                blast_protection = (
                    exterior_score * 0.3
                    + roof_score * 0.3
                    + mamad_score * 0.2
                    + (room_specific_score * 0.2 if current_room else 0.0)
                )
                blast_protection = max(0.0, min(100.0, blast_protection))

                # ── Store results ──
                point.safety_score = round(safety_score, 2)
                point.risk_level = risk_level
                point.evacuation_time = round(evac_time, 2)
                point.blast_protection = round(blast_protection, 2)
                point.factors = {
                    'exterior_distance':   round(exterior_score, 2),
                    'mamad_proximity':     round(mamad_score, 2),
                    'opening_penalty':     round(opening_penalty, 2),
                    'debris_risk':         round(debris_risk, 2),
                    'evacuation':          round(evacuation_score, 2),
                    'roof_protection':     round(roof_score, 2),
                    'room_specific':       round(room_specific_score, 2),
                }

            except Exception as e:
                print(f"[HEATMAP_DEBUG] ERROR calculating risk for point ({point.x}, {point.y}): {e}")
                import traceback
                print(traceback.format_exc())
                # Graceful fallback – mark as medium risk
                point.safety_score = 40.0
                point.risk_level = RiskLevel.MEDIUM
                point.factors = {'error_fallback': 1.0}
                point.evacuation_time = 120.0
                point.blast_protection = 30.0

        # ── Post-loop debug summary (raw / absolute scores) ──
        safety_vals = [p.safety_score for p in grid_points]
        print(f"[HEATMAP_DEBUG] Raw absolute scores – "
              f"range {min(safety_vals):.1f}-{max(safety_vals):.1f}, "
              f"avg {sum(safety_vals)/len(safety_vals):.1f}")

        # ══════════════════════════════════════════════════════════════
        # ── RELATIVE NORMALIZATION PASS ──
        # The absolute scores grade the building against an *ideal*
        # safe-room standard.  A normal apartment with no MAMAD and
        # ordinary glazing will score LOW everywhere, producing a
        # uniformly orange/red heatmap that tells the user nothing.
        #
        # The purpose of SafeMad is to answer: "WHERE in MY home is
        # relatively safer?"  So we rescale the scores of interior
        # points to use the full 5-95 range, preserving the ranking
        # while making the gradient visually meaningful.
        #
        # Outside-building points (score == 5.0) are excluded from
        # normalisation and kept at their fixed penalty score.
        # ══════════════════════════════════════════════════════════════
        NORM_FLOOR = 5.0    # lowest normalised score for interior points
        NORM_CEIL  = 95.0   # highest normalised score for interior points

        interior_points = [p for p in grid_points if p.factors.get('outside_building') != 1.0]

        if interior_points:
            raw_min = min(p.safety_score for p in interior_points)
            raw_max = max(p.safety_score for p in interior_points)
            raw_range = raw_max - raw_min

            print(f"[HEATMAP_DEBUG] Relative normalisation – "
                  f"interior raw range {raw_min:.1f}-{raw_max:.1f} "
                  f"→ mapping to {NORM_FLOOR:.0f}-{NORM_CEIL:.0f}")

            if raw_range > 1.0:
                # Enough spread to normalise meaningfully
                # Pre-compute blast protection range for normalisation
                bp_raw_min = min(p.blast_protection for p in interior_points)
                bp_raw_max = max(p.blast_protection for p in interior_points)
                bp_range = bp_raw_max - bp_raw_min

                for point in interior_points:
                    # Linear rescale: raw_min → NORM_FLOOR, raw_max → NORM_CEIL
                    t = (point.safety_score - raw_min) / raw_range
                    normalised = NORM_FLOOR + t * (NORM_CEIL - NORM_FLOOR)
                    normalised = max(NORM_FLOOR, min(NORM_CEIL, normalised))

                    # Store the raw absolute score for transparency
                    point.factors['raw_absolute_score'] = round(point.safety_score, 2)

                    point.safety_score = round(normalised, 2)

                    # Re-derive risk level from the normalised score
                    risk_score = 100.0 - point.safety_score
                    point.risk_level = self._determine_risk_level_from_risk(risk_score)

                    # Normalise blast protection on same scale
                    if bp_range > 1.0:
                        bp_t = (point.blast_protection - bp_raw_min) / bp_range
                        point.blast_protection = round(
                            NORM_FLOOR + bp_t * (NORM_CEIL - NORM_FLOOR), 2
                        )
            else:
                # All interior points have nearly identical raw scores –
                # spread them around the midpoint so the heatmap isn't flat
                print(f"[HEATMAP_DEBUG] Very narrow raw range ({raw_range:.2f}), "
                      f"applying mid-range spread")
                for point in interior_points:
                    point.safety_score = 50.0
                    point.risk_level = RiskLevel.MEDIUM

        # Final normalised summary
        safety_vals = [p.safety_score for p in grid_points]
        print(f"[HEATMAP_DEBUG] Normalised scores – "
              f"range {min(safety_vals):.1f}-{max(safety_vals):.1f}, "
              f"avg {sum(safety_vals)/len(safety_vals):.1f}")

        # Generate visualizations
        try:
            print(f"[HEATMAP_DEBUG] Generating visualizations for {width}x{height} grid")
            heatmap_visualizations = self._generate_heatmap_visualizations(grid_points, width, height)
            print(f"[HEATMAP_DEBUG] Visualizations generated successfully")
        except Exception as e:
            print(f"[HEATMAP_DEBUG] ERROR generating visualizations: {e}")
            import traceback
            print(f"[HEATMAP_DEBUG] Visualization error traceback: {traceback.format_exc()}")
            # Create minimal fallback visualization
            heatmap_visualizations = {
                'safety_heatmap': [[50.0 for _ in range(width//20)] for _ in range(height//20)],
                'evacuation_heatmap': [[50.0 for _ in range(width//20)] for _ in range(height//20)],
                'protection_heatmap': [[50.0 for _ in range(width//20)] for _ in range(height//20)],
                'grid_resolution': self.grid_resolution
            }
        
        # Identify safe and risk zones
        safe_zones = self._identify_safe_zones(grid_points)
        risk_zones = self._identify_risk_zones(grid_points)
        
        # Generate recommendations
        recommendations = self._generate_safety_recommendations(
            grid_points, safe_zones, risk_zones, rooms
        )
        
        # Calculate statistics
        statistics = self._calculate_statistics(grid_points)
        
        # Serialize grid points for response
        serialized_points = [self._serialize_grid_point(point) for point in grid_points]
        
        # ---------------- Debug summary ----------------
        if self.debug:
            safety_vals = [p.safety_score for p in grid_points]
            print(f"[DEBUG] Safety range {min(safety_vals):.1f}-{max(safety_vals):.1f} avg {sum(safety_vals)/len(safety_vals):.1f}")
            outside = [p for p in grid_points if not self._find_room_for_point(p, rooms)]
            print(f"[DEBUG] Outside grid points: {len(outside)}; sample: {[(p.x, p.y, p.safety_score) for p in outside[:10]]}")
        
        return {
            'heatmap_data': {
                'grid_points': serialized_points,
                'visualizations': heatmap_visualizations,
                'safe_zones': safe_zones,
                'risk_zones': risk_zones,
                'statistics': statistics,
                'recommendations': recommendations
            },
            'metadata': {
                'grid_resolution': self.grid_resolution,
                'total_points': len(grid_points),
                'floor_plan_dimensions': {'width': width, 'height': height},
                'mamad_rooms_count': len(mamad_rooms)
            }
        }

    def _calculate_floor_plan_dimensions(self, floor_plan_data: Dict[str, Any], house_boundaries: Dict, rooms: List) -> Tuple[int, int]:
        """Calculate floor plan dimensions from boundaries or rooms"""
        # First priority: use image_dimensions from the payload
        image_dimensions = floor_plan_data.get('image_dimensions', {})
        if image_dimensions:
            width = image_dimensions.get('width', 0)
            height = image_dimensions.get('height', 0)
            if width > 0 and height > 0:
                print(f"[HEATMAP_DEBUG] Using image dimensions: {width}x{height}")
                return int(width), int(height)
        
        # Second priority: use house boundaries
        if house_boundaries and 'exterior_perimeter' in house_boundaries:
            perimeter = house_boundaries['exterior_perimeter']
            max_x = max(p.get('x', 0) for p in perimeter)
            max_y = max(p.get('y', 0) for p in perimeter)
            print(f"[HEATMAP_DEBUG] Using house boundaries dimensions: {int(max_x)}x{int(max_y)}")
            return int(max_x), int(max_y)
        
        # Third priority: fall back to room boundaries
        if rooms:
            max_x = 0
            max_y = 0
            for room in rooms:
                boundaries = room.get('boundaries', [])
                if boundaries:
                    for boundary in boundaries:
                        max_x = max(max_x, boundary.get('x', 0))
                        max_y = max(max_y, boundary.get('y', 0))
            if max_x > 0 and max_y > 0:
                print(f"[HEATMAP_DEBUG] Using room boundaries dimensions: {int(max_x)}x{int(max_y)}")
            return int(max_x) if max_x > 0 else 800, int(max_y) if max_y > 0 else 600
        
        print(f"[HEATMAP_DEBUG] Using default dimensions: 800x600")
        return 800, 600  # Default dimensions

    def _create_safety_grid(self, width: int, height: int) -> List[GridPoint]:
        """Create grid points for safety analysis"""
        grid_points = []
        
        # Ensure we cover the entire area by extending to the full dimensions
        # Add some padding to ensure complete coverage
        extended_width = width + self.grid_resolution
        extended_height = height + self.grid_resolution
        
        for y in range(0, extended_height, self.grid_resolution):
            for x in range(0, extended_width, self.grid_resolution):
                point = GridPoint(
                    x=x,
                    y=y,
                    safety_score=0.0,
                    risk_level=RiskLevel.MEDIUM,
                    factors={},
                    evacuation_time=0.0,
                    blast_protection=0.0
                )
                grid_points.append(point)
        
        print(f"[HEATMAP_DEBUG] Created grid: {len(grid_points)} points covering {width}x{height} -> {extended_width}x{extended_height}")
        print(f"[HEATMAP_DEBUG] Grid resolution: {self.grid_resolution}, expected points: {(extended_width//self.grid_resolution + 1) * (extended_height//self.grid_resolution + 1)}")
        
        return grid_points

    def _is_near_external_wall(self, pos, external_walls, threshold=30):
        """Check if a position is near any external wall segment (within threshold in pixels)"""
        for wall in external_walls:
            start = wall.get('segment_start', {})
            end = wall.get('segment_end', {})
            if start and end:
                dist = self._point_to_line_distance(
                    pos.get('x', 0), pos.get('y', 0),
                    start.get('x', 0), start.get('y', 0),
                    end.get('x', 0), end.get('y', 0)
                )
                if dist <= threshold:
                    return True
        return False

    def _classify_external_openings(self, windows, doors, external_walls):
        """Mark windows/doors as external if near an external wall"""
        for w in windows:
            pos = w.get('position', {})
            w['is_external'] = self._is_near_external_wall(pos, external_walls)
        for d in doors:
            pos = d.get('position', {})
            d['is_external'] = self._is_near_external_wall(pos, external_walls)

    def _is_point_inside_house_boundary(self, point: GridPoint, house_boundary_points: List[Dict[str, float]]) -> bool:
        """Check if a grid point is inside the house boundary polygon"""
        if not house_boundary_points or len(house_boundary_points) < 3:
            return False
        
        return self._point_in_polygon(point.x, point.y, house_boundary_points)

    def _calculate_exterior_distance(self, point: GridPoint, external_walls: List[Dict[str, Any]]) -> float:
        """Calculate distance from exterior walls"""
        if not external_walls:
            return 1.0
        
        min_distance = float('inf')
        
        for wall in external_walls:
            start = wall.get('segment_start', {})
            end = wall.get('segment_end', {})
            
            if start and end:
                distance = self._point_to_line_distance(
                    point.x, point.y,
                    start.get('x', 0), start.get('y', 0),
                    end.get('x', 0), end.get('y', 0)
                )
                min_distance = min(min_distance, distance)
        
        return max(0, min_distance * self.pixel_to_meter_ratio)

    def _calculate_evacuation_time(self, point: GridPoint, doors: List[Dict[str, Any]]) -> float:
        """Calculate estimated evacuation time from this point"""
        exits = [d for d in doors if d.get('is_external', False) or d.get('leads_to_exit', False)]
        
        if not exits:
            return 300.0
        
        min_distance = float('inf')
        
        for exit_door in exits:
            exit_pos = exit_door.get('position', {})
            exit_x = exit_pos.get('x', 0)
            exit_y = exit_pos.get('y', 0)
            
            distance = math.sqrt((point.x - exit_x)**2 + (point.y - exit_y)**2)
            min_distance = min(min_distance, distance)
        
        distance_meters = min_distance * self.pixel_to_meter_ratio
        evacuation_time = distance_meters / 1.0
        route_complexity_penalty = min(30, distance_meters * 0.2)
        
        return evacuation_time + route_complexity_penalty

    def _generate_heatmap_visualizations(self, grid_points: List[GridPoint], width: int, height: int) -> Dict[str, Any]:
        """Generate heatmap visualization data"""
        grid_width = width // self.grid_resolution + 1
        grid_height = height // self.grid_resolution + 1
        
        safety_matrix = np.zeros((grid_height, grid_width))
        evacuation_matrix = np.zeros((grid_height, grid_width))
        protection_matrix = np.zeros((grid_height, grid_width))
        
        for point in grid_points:
            grid_x = min(point.x // self.grid_resolution, grid_width - 1)
            grid_y = min(point.y // self.grid_resolution, grid_height - 1)
            
            safety_matrix[grid_y, grid_x] = point.safety_score
            evacuation_matrix[grid_y, grid_x] = max(0, 300 - point.evacuation_time)
            protection_matrix[grid_y, grid_x] = point.blast_protection
        
        # Apply smoothing
        safety_matrix = gaussian_filter(safety_matrix, sigma=1)
        evacuation_matrix = gaussian_filter(evacuation_matrix, sigma=1)
        protection_matrix = gaussian_filter(protection_matrix, sigma=1)
        
        return {
            'safety_heatmap': safety_matrix.tolist(),
            'evacuation_heatmap': evacuation_matrix.tolist(),
            'protection_heatmap': protection_matrix.tolist(),
            'grid_resolution': self.grid_resolution
        }

    def _identify_safe_zones(self, grid_points: List[GridPoint]) -> List[Dict[str, Any]]:
        """Identify areas with high safety scores"""
        safe_zones = []
        high_safety_points = [p for p in grid_points if p.safety_score >= 70]
        
        if not high_safety_points:
            return safe_zones
        
        zones = []
        for point in high_safety_points:
            added_to_zone = False
            
            for zone in zones:
                for zone_point in zone:
                    distance = math.sqrt((point.x - zone_point.x)**2 + (point.y - zone_point.y)**2)
                    if distance <= self.grid_resolution * 1.5:
                        zone.append(point)
                        added_to_zone = True
                        break
                
                if added_to_zone:
                    break
            
            if not added_to_zone:
                zones.append([point])
        
        for i, zone in enumerate(zones):
            if len(zone) >= 4:
                avg_safety = sum(p.safety_score for p in zone) / len(zone)
                center_x = sum(p.x for p in zone) / len(zone)
                center_y = sum(p.y for p in zone) / len(zone)
                
                safe_zones.append({
                    'zone_id': f'safe_zone_{i}',
                    'center': {'x': center_x, 'y': center_y},
                    'average_safety_score': avg_safety,
                    'area_points': len(zone),
                    'estimated_capacity': len(zone) * 2,
                    'points': [{'x': p.x, 'y': p.y, 'score': p.safety_score} for p in zone]
                })
        
        return safe_zones

    def _identify_risk_zones(self, grid_points: List[GridPoint]) -> List[Dict[str, Any]]:
        """Identify areas with low safety scores"""
        risk_zones = []
        low_safety_points = [p for p in grid_points if p.safety_score <= 30]
        
        if not low_safety_points:
            return risk_zones
        
        zones = []
        for point in low_safety_points:
            added_to_zone = False
            
            for zone in zones:
                for zone_point in zone:
                    distance = math.sqrt((point.x - zone_point.x)**2 + (point.y - zone_point.y)**2)
                    if distance <= self.grid_resolution * 1.5:
                        zone.append(point)
                        added_to_zone = True
                        break
                
                if added_to_zone:
                    break
            
            if not added_to_zone:
                zones.append([point])
        
        for i, zone in enumerate(zones):
            if len(zone) >= 4:
                avg_safety = sum(p.safety_score for p in zone) / len(zone)
                center_x = sum(p.x for p in zone) / len(zone)
                center_y = sum(p.y for p in zone) / len(zone)
                
                risk_zones.append({
                    'zone_id': f'risk_zone_{i}',
                    'center': {'x': center_x, 'y': center_y},
                    'average_safety_score': avg_safety,
                    'area_points': len(zone),
                    'warning_level': 'high' if avg_safety < 20 else 'medium',
                    'points': [{'x': p.x, 'y': p.y, 'score': p.safety_score} for p in zone]
                })
        
        return risk_zones

    def _generate_safety_recommendations(
        self, 
        grid_points: List[GridPoint], 
        safe_zones: List[Dict[str, Any]], 
        risk_zones: List[Dict[str, Any]], 
        rooms: List[Dict[str, Any]]
    ) -> List[Dict[str, str]]:
        """Generate safety recommendations based on heatmap analysis"""
        recommendations = []
        
        if safe_zones:
            best_safe_zone = max(safe_zones, key=lambda z: z['average_safety_score'])
            recommendations.append({
                'type': 'safe_zone',
                'priority': 'high',
                'title': 'Primary Safe Zone Identified',
                'description': f'The safest area is at coordinates ({best_safe_zone["center"]["x"]:.0f}, {best_safe_zone["center"]["y"]:.0f}) with safety score {best_safe_zone["average_safety_score"]:.1f}',
                'action': 'Designate this area as primary emergency shelter location'
            })
        
        if risk_zones:
            worst_risk_zone = min(risk_zones, key=lambda z: z['average_safety_score'])
            recommendations.append({
                'type': 'risk_zone',
                'priority': 'critical',
                'title': 'High Risk Area Identified',
                'description': f'Dangerous area at coordinates ({worst_risk_zone["center"]["x"]:.0f}, {worst_risk_zone["center"]["y"]:.0f}) with safety score {worst_risk_zone["average_safety_score"]:.1f}',
                'action': 'Avoid this area during emergencies, consider structural improvements'
            })
        
        avg_evacuation_time = sum(p.evacuation_time for p in grid_points) / len(grid_points)
        if avg_evacuation_time > 120:
            recommendations.append({
                'type': 'evacuation',
                'priority': 'high',
                'title': 'Evacuation Routes Need Improvement',
                'description': f'Average evacuation time is {avg_evacuation_time:.1f} seconds',
                'action': 'Consider adding additional exits or improving pathway accessibility'
            })
        
        mamad_rooms = [r for r in rooms if r.get('is_mamad', False) or 'mamad' in r.get('type', '').lower()]
        if not mamad_rooms:
            recommendations.append({
                'type': 'mamad',
                'priority': 'high',
                'title': 'No Mamad (Safe Room) Detected',
                'description': 'No reinforced safe room found in floor plan',
                'action': 'Consider designating or constructing a Mamad for optimal protection'
            })
        
        return recommendations

    def _calculate_statistics(self, grid_points: List[GridPoint]) -> Dict[str, Any]:
        """Calculate overall statistics for the heatmap"""
        safety_scores = [p.safety_score for p in grid_points]
        evacuation_times = [p.evacuation_time for p in grid_points]
        
        return {
            'total_grid_points': len(grid_points),
            'average_safety_score': sum(safety_scores) / len(safety_scores),
            'min_safety_score': min(safety_scores),
            'max_safety_score': max(safety_scores),
            'average_evacuation_time': sum(evacuation_times) / len(evacuation_times),
            'safe_points_count': len([p for p in grid_points if p.safety_score >= 70]),
            'risk_points_count': len([p for p in grid_points if p.safety_score <= 30]),
            'coverage_area_m2': len(grid_points) * (self.grid_resolution * self.pixel_to_meter_ratio) ** 2
        }

    # Helper methods
    def _find_room_for_point(self, point: GridPoint, rooms: List[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
        """Find which room contains the given point"""
        if not rooms:
            return None
            
        for room in rooms:
            boundaries = room.get('boundaries', [])
            if not boundaries:
                # Room has no boundaries, skip it
                continue
            if not isinstance(boundaries, list) or len(boundaries) < 3:
                # Invalid boundary format
                continue
            if self._point_in_polygon(point.x, point.y, boundaries):
                return room
        return None

    def _find_assessment_for_room(self, room: Dict[str, Any], assessments: List[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
        """Find safety assessment for a specific room"""
        if not room or not assessments:
            return None
        
        room_id = room.get('id', room.get('room_id', ''))
        
        for assessment in assessments:
            if assessment.get('room_id') == room_id:
                return assessment
        
        return None

    def _point_in_polygon(self, x: float, y: float, polygon: List[Dict[str, float]]) -> bool:
        """Check if point is inside polygon using ray casting algorithm"""
        if len(polygon) < 3:
            return False
        
        inside = False
        j = len(polygon) - 1
        
        for i in range(len(polygon)):
            xi, yi = polygon[i].get('x', 0), polygon[i].get('y', 0)
            xj, yj = polygon[j].get('x', 0), polygon[j].get('y', 0)
            
            if ((yi > y) != (yj > y)) and (x < (xj - xi) * (y - yi) / (yj - yi) + xi):
                inside = not inside
            j = i
        
        return inside

    def _point_to_line_distance(self, px: float, py: float, x1: float, y1: float, x2: float, y2: float) -> float:
        """Calculate distance from point to line segment"""
        A = px - x1
        B = py - y1
        C = x2 - x1
        D = y2 - y1
        
        dot = A * C + B * D
        len_sq = C * C + D * D
        
        if len_sq == 0:
            return math.sqrt(A * A + B * B)
        
        param = dot / len_sq
        
        if param < 0:
            xx, yy = x1, y1
        elif param > 1:
            xx, yy = x2, y2
        else:
            xx = x1 + param * C
            yy = y1 + param * D
        
        dx = px - xx
        dy = py - yy
        return math.sqrt(dx * dx + dy * dy)

    def _calculate_room_size_factor(self, room: Dict[str, Any]) -> float:
        """Calculate room size factor for safety"""
        if not room:
            return 50.0
        
        area = room.get('area_m2', 0)
        
        if 10 <= area <= 20:
            return 80.0
        elif 5 <= area < 10 or 20 < area <= 30:
            return 60.0
        elif area < 5:
            return 30.0
        else:
            return 40.0

    def _calculate_reinforced_area(self, room: Dict[str, Any], assessment: Dict[str, Any]) -> float:
        """Calculate reinforced area bonus"""
        if not room or not assessment:
            return 0.0
        
        responses = assessment.get('responses', {})
        reinforcement_score = 0.0
        
        if responses.get('wall_material', '').lower() in ['concrete', 'steel']:
            reinforcement_score += 20
        
        if 'thick' in responses.get('wall_thickness', '').lower():
            reinforcement_score += 15
        
        return reinforcement_score

    def _calculate_corner_effect(self, point: GridPoint, rooms: List[Dict[str, Any]]) -> float:
        """Calculate corner protection effect"""
        current_room = self._find_room_for_point(point, rooms)
        
        if not current_room:
            return 0.0
        
        boundaries = current_room.get('boundaries', [])
        if len(boundaries) < 3:
            return 0.0
        
        min_corner_distance = float('inf')
        
        for boundary in boundaries:
            corner_x = boundary.get('x', 0)
            corner_y = boundary.get('y', 0)
            distance = math.sqrt((point.x - corner_x)**2 + (point.y - corner_y)**2)
            min_corner_distance = min(min_corner_distance, distance)
        
        if min_corner_distance < 50:
            return 70 * (1 - min_corner_distance / 50)
        
        return 0.0

    def _calculate_evacuation_distance(self, point: GridPoint, doors: List[Dict[str, Any]]) -> float:
        """Calculate evacuation route distance"""
        exits = [d for d in doors if d.get('is_external', False) or d.get('leads_to_exit', False)]
        
        if not exits:
            return 100.0
        
        min_distance = float('inf')
        
        for exit_door in exits:
            exit_pos = exit_door.get('position', {})
            exit_x = exit_pos.get('x', 0)
            exit_y = exit_pos.get('y', 0)
            
            distance = math.sqrt((point.x - exit_x)**2 + (point.y - exit_y)**2)
            min_distance = min(min_distance, distance)
        
        return min_distance * self.pixel_to_meter_ratio

    def _calculate_exit_access(self, point: GridPoint, doors: List[Dict[str, Any]]) -> float:
        """Calculate emergency exit access score"""
        exits = [d for d in doors if d.get('is_external', False) or d.get('leads_to_exit', False)]
        
        if not exits:
            return 0.0
        
        if len(exits) >= 2:
            return 80.0
        elif len(exits) == 1:
            return 50.0
        else:
            return 0.0

    def _calculate_debris_risk(self, point: GridPoint, windows: List[Dict[str, Any]]) -> float:
        """Calculate debris risk from windows"""
        debris_risk = 0.0
        
        for window in windows:
            window_pos = window.get('position', {})
            window_x = window_pos.get('x', 0)
            window_y = window_pos.get('y', 0)
            
            distance = math.sqrt((point.x - window_x)**2 + (point.y - window_y)**2)
            
            if distance < 100:
                size_factor = {
                    'small': 1.0,
                    'medium': 1.5,
                    'large': 2.0,
                    'floor_to_ceiling': 3.0
                }.get(window.get('size_category', 'medium'), 1.5)
                
                proximity_factor = max(0, 100 - distance) / 100
                debris_risk += size_factor * proximity_factor * 10
        
        return min(100, debris_risk)

    def _glazing_resistance(self, glazing_type: str) -> float:
        """Return mapped glazing/door resistance factor in range 0-1"""
        if not glazing_type:
            glazing_type = 'unknown'
        return self.glazing_resistance.get(glazing_type.lower(), self.glazing_resistance['unknown'])

    def _calculate_opening_penalty(
        self,
        point: GridPoint,
        windows: List[Dict[str, Any]],
        doors: List[Dict[str, Any]]
    ) -> float:
        """Aggregate penalty (0-100) for proximity to weak openings"""
        penalty = 0.0

        # Windows – larger base penalty
        for w in windows:
            pos = w.get('position', {})
            d = self._euclidean_distance(point.x, point.y, pos.get('x', 0), pos.get('y', 0))
            if d < 120:  # 6 m radius
                base = 60  # max penalty from a single window
                R = self._glazing_resistance(w.get('glazing_type', 'ordinary'))
                penalty += (1 - R) * (120 - d) / 120 * base

        # Doors – lower base penalty (wood/metal)
        for d_open in doors:
            pos = d_open.get('position', {})
            d = self._euclidean_distance(point.x, point.y, pos.get('x', 0), pos.get('y', 0))
            if d < 120:
                base = 40
                material_res = self._glazing_resistance(d_open.get('door_grade', 'ordinary'))
                penalty += (1 - material_res) * (120 - d) / 120 * base

        return min(100.0, penalty)

    def _euclidean_distance(self, x1: float, y1: float, x2: float, y2: float) -> float:
        return math.hypot(x1 - x2, y1 - y2)

    def _calculate_mamad_distance_bonus(
        self,
        point: GridPoint,
        mamad_rooms: List[Dict[str, Any]]
    ) -> float:
        """Exponential decay bonus based on distance to nearest MAMAD wall"""
        if not mamad_rooms:
            return 0.0

        min_d = float('inf')
        for room in mamad_rooms:
            boundaries = room.get('boundaries') or room.get('boundary') or {}
            # Support both list of points or dict with 'points'
            polygon = []
            if isinstance(boundaries, list):
                polygon = boundaries
            elif isinstance(boundaries, dict):
                polygon = boundaries.get('points', [])
            d = self._point_to_polygon_distance(point.x, point.y, polygon)
            min_d = min(min_d, d)

        # Grid resolution ≈ 0.05 m/px (from elsewhere) → decay length 70 px ≈ 3.5 m
        bonus = 90 * math.exp(-min_d / 70) if min_d != float('inf') else 0.0
        return bonus

    def _point_to_polygon_distance(self, x: float, y: float, polygon: List[Dict[str, float]]) -> float:
        """Approximate min distance from a point to polygon vertices"""
        if not polygon:
            return float('inf')
        return min(self._euclidean_distance(x, y, p.get('x', 0), p.get('y', 0)) for p in polygon)

    def _calculate_roof_protection(self, assessment: Dict[str, Any]) -> float:
        """Map roof material/thickness to protection (0-100)"""
        if not assessment:
            return 50.0

        responses = assessment.get('responses', {})
        material = responses.get('roof_material', 'concrete').lower()
        thickness = responses.get('roof_thickness', '20cm').lower()

        material_values = {
            'reinforced_concrete': 90,
            'concrete': 80,
            'hollow_block': 60,
            'steel': 70,
            'wood': 30,
            'unknown': 50
        }

        base = material_values.get(material, 50)

        try:
            num_cm = float(''.join(filter(str.isdigit, thickness)))
            if num_cm >= 25:
                base += 10
            elif num_cm <= 10:
                base -= 10
        except Exception:
            pass

        return max(0.0, min(100.0, base))

    def _serialize_grid_point(self, point: GridPoint) -> Dict[str, Any]:
        """Convert GridPoint to serializable dictionary"""
        return {
            'x': point.x,
            'y': point.y,
            'safety_score': round(point.safety_score, 1),
            'risk_level': point.risk_level.name,
            'factors': {k: round(v, 2) for k, v in point.factors.items()},
            'evacuation_time': round(point.evacuation_time, 1),
            'blast_protection': round(point.blast_protection, 1)
        }

    # ------------------------------------------------------------------
    # NEW helper – distance from a point to the nearest edge of polygon
    # ------------------------------------------------------------------
    def _point_to_polygon_edge_distance(self, x: float, y: float, polygon: List[Dict[str, float]]) -> float:
        """Return minimum distance (pixels) from the point (x,y) to any edge of the polygon."""
        if not polygon or len(polygon) < 2:
            return float('inf')

        min_dist = float('inf')
        n = len(polygon)
        for i in range(n):
            p1 = polygon[i]
            p2 = polygon[(i + 1) % n]
            d = self._point_to_line_distance(
                x, y,
                p1.get('x', 0), p1.get('y', 0),
                p2.get('x', 0), p2.get('y', 0)
            )
            min_dist = min(min_dist, d)
        return min_dist

    # ------------------------------------------------------------------
    # Simple helper – map numeric RISK score to categorical RiskLevel
    # ------------------------------------------------------------------
    def _determine_risk_level_from_risk(self, risk_score: float) -> RiskLevel:
        """Return RiskLevel based on *risk* score (0-100, higher = more risky)."""
        if risk_score >= 80:
            return RiskLevel.VERY_HIGH
        elif risk_score >= 65:
            return RiskLevel.HIGH
        elif risk_score >= 45:
            return RiskLevel.MEDIUM
        elif risk_score >= 25:
            return RiskLevel.LOW
        else:
            return RiskLevel.VERY_LOW