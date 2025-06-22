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

class ExplosiveRiskHeatmapService:
    def __init__(self):
        self.grid_resolution = 20  # Grid cell size in pixels
        self.blast_radius_meters = 50  # Effective blast radius in meters
        self.pixel_to_meter_ratio = 0.1  # Default: 10 pixels = 1 meter
        
        # Material protection factors (0-1, higher = better protection)
        self.material_protection = {
            'reinforced_concrete': 0.95,
            'concrete': 0.85,
            'concrete_block': 0.75,
            'brick': 0.65,
            'steel': 0.90,
            'drywall': 0.30,
            'wood': 0.20,
            'unknown': 0.40
        }
        
        # Wall thickness protection (cm to protection factor)
        self.thickness_protection_values = {
            'very_thick': 0.90,  # >30cm
            'thick': 0.75,       # 20-30cm
            'medium': 0.50,      # 10-20cm
            'thin': 0.25,        # <10cm
            'unknown': 0.40
        }

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
        
        print(f"[HEATMAP_DEBUG] Extracted data:")
        print(f"   house_boundaries: {bool(house_boundaries)}")
        print(f"   rooms: {len(rooms)}")
        print(f"   external_walls: {len(external_walls)}")
        print(f"   windows: {len(windows)}")
        print(f"   doors: {len(doors)}")
        print(f"   safety_assessments: {len(safety_assessments)}")
        
        # Debug logging for MAMAD rooms
        print(f"🔥 Heatmap generation - Total rooms received: {len(rooms)}")
        mamad_rooms = [r for r in rooms if r.get('is_mamad', False) or 'mamad' in r.get('type', '').lower()]
        print(f"🔒 MAMAD rooms received: {len(mamad_rooms)}")
        for mamad_room in mamad_rooms:
            print(f"   MAMAD: {mamad_room.get('name', 'Unknown')} (Type: {mamad_room.get('type', 'Unknown')})")
        
        # Calculate floor plan dimensions
        try:
            width, height = self._calculate_floor_plan_dimensions(house_boundaries, rooms)
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
        
        # Calculate risk factors for each grid point
        for point in grid_points:
            risk_factors = self._calculate_risk_factors(
                point, rooms, external_walls, windows, doors, safety_assessments
            )
            
            # Calculate composite safety score
            point.safety_score = self._calculate_composite_safety_score(risk_factors)
            point.risk_level = self._determine_risk_level(point.safety_score)
            point.factors = risk_factors.__dict__
            
            # Calculate evacuation time
            point.evacuation_time = self._calculate_evacuation_time(point, doors)
            
            # Calculate blast protection
            point.blast_protection = self._calculate_blast_protection(
                point, external_walls, safety_assessments
            )
        
        # Debug logging for safety scores
        high_safety_points = [p for p in grid_points if p.safety_score >= 80]
        print(f"🟢 High safety points (>=80): {len(high_safety_points)}")
        if high_safety_points:
            max_safety = max(p.safety_score for p in grid_points)
            print(f"   Max safety score: {max_safety}")
        
        # Generate visualizations
        heatmap_visualizations = self._generate_heatmap_visualizations(grid_points, width, height)
        
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

    def _calculate_floor_plan_dimensions(self, house_boundaries: Dict, rooms: List) -> Tuple[int, int]:
        """Calculate floor plan dimensions from boundaries or rooms"""
        if house_boundaries and 'exterior_perimeter' in house_boundaries:
            perimeter = house_boundaries['exterior_perimeter']
            max_x = max(p.get('x', 0) for p in perimeter)
            max_y = max(p.get('y', 0) for p in perimeter)
            return int(max_x), int(max_y)
        
        # Fall back to room boundaries
        if rooms:
            max_x = 0
            max_y = 0
            for room in rooms:
                boundaries = room.get('boundaries', [])
                if boundaries:
                    for boundary in boundaries:
                        max_x = max(max_x, boundary.get('x', 0))
                        max_y = max(max_y, boundary.get('y', 0))
            return int(max_x) if max_x > 0 else 800, int(max_y) if max_y > 0 else 600
        
        return 800, 600  # Default dimensions

    def _create_safety_grid(self, width: int, height: int) -> List[GridPoint]:
        """Create grid points for safety analysis"""
        grid_points = []
        
        for y in range(0, height, self.grid_resolution):
            for x in range(0, width, self.grid_resolution):
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
        
        return grid_points

    def _calculate_risk_factors(
        self, 
        point: GridPoint, 
        rooms: List[Dict[str, Any]],
        external_walls: List[Dict[str, Any]],
        windows: List[Dict[str, Any]],
        doors: List[Dict[str, Any]],
        safety_assessments: List[Dict[str, Any]]
    ) -> ExplosiveRiskFactors:
        """Calculate all risk factors for a grid point"""
        
        factors = ExplosiveRiskFactors()
        
        # Find which room this point belongs to
        current_room = self._find_room_for_point(point, rooms)
        current_assessment = self._find_assessment_for_room(current_room, safety_assessments)
        
        if current_room and current_assessment:
            # Structural protection factors
            factors.wall_material_protection = self._calculate_wall_protection(current_assessment)
            factors.wall_thickness_protection = self._calculate_thickness_protection(current_assessment)
            factors.ceiling_protection = self._calculate_ceiling_protection(current_assessment)
            
            # Room-specific factors
            factors.room_size_factor = self._calculate_room_size_factor(current_room)
            factors.mamad_protection = self._calculate_mamad_protection(current_room, current_assessment)
            factors.reinforced_area = self._calculate_reinforced_area(current_room, current_assessment)
            
            # Debug logging for MAMAD rooms
            if current_room.get('is_mamad', False) or 'mamad' in current_room.get('type', '').lower():
                print(f"🔒 Grid point ({point.x}, {point.y}) is in MAMAD room: {current_room.get('name', 'Unknown')}")
                print(f"   MAMAD protection factor: {factors.mamad_protection}")
        
        # Distance-based factors
        factors.distance_from_exterior = self._calculate_exterior_distance(point, external_walls)
        factors.distance_from_windows = self._calculate_window_distance(point, windows)
        factors.distance_from_doors = self._calculate_door_distance(point, doors)
        factors.corner_effect = self._calculate_corner_effect(point, rooms)
        
        # Evacuation factors
        factors.evacuation_route_distance = self._calculate_evacuation_distance(point, doors)
        factors.emergency_exit_access = self._calculate_exit_access(point, doors)
        
        # Environmental factors
        factors.debris_risk = self._calculate_debris_risk(point, windows)
        
        return factors

    def _calculate_composite_safety_score(self, factors: ExplosiveRiskFactors) -> float:
        """
        Calculate composite safety score (0-100) based on all risk factors
        """
        
        # Weights for different factor categories
        weights = {
            'structural': 0.35,      # Wall protection, thickness, materials
            'positioning': 0.25,     # Distance from exterior, windows, doors
            'evacuation': 0.20,      # Access to exits, evacuation routes
            'environmental': 0.10,   # Room size, debris risk
            'special': 0.10          # Mamad, reinforced areas
        }
        
        # Structural protection score (0-100)
        structural_score = (
            factors.wall_material_protection * 0.40 +
            factors.wall_thickness_protection * 0.30 +
            factors.ceiling_protection * 0.20 +
            factors.floor_material * 0.10
        )
        
        # Positioning score (0-100)
        positioning_score = (
            min(100, factors.distance_from_exterior * 10) * 0.4 +
            min(100, factors.distance_from_windows * 8) * 0.3 +
            min(100, factors.distance_from_doors * 6) * 0.2 +
            factors.corner_effect * 0.1
        )
        
        # Evacuation score (0-100)
        evacuation_score = (
            min(100, (1 / max(0.1, factors.evacuation_route_distance)) * 50) * 0.6 +
            factors.emergency_exit_access * 0.4
        )
        
        # Environmental score (0-100)
        env_score = (
            factors.room_size_factor * 0.5 +
            max(0, 100 - factors.debris_risk * 10) * 0.3 +
            factors.ventilation_factor * 0.2
        )
        
        # Special protection score (0-100)
        special_score = (
            factors.mamad_protection * 0.7 +
            factors.reinforced_area * 0.3
        )
        
        # Calculate weighted total
        total_score = (
            structural_score * weights['structural'] +
            positioning_score * weights['positioning'] +
            evacuation_score * weights['evacuation'] +
            env_score * weights['environmental'] +
            special_score * weights['special']
        )
        
        return max(0, min(100, total_score))

    def _determine_risk_level(self, safety_score: float) -> RiskLevel:
        """Determine risk level based on safety score"""
        if safety_score >= 80:
            return RiskLevel.VERY_LOW
        elif safety_score >= 65:
            return RiskLevel.LOW
        elif safety_score >= 45:
            return RiskLevel.MEDIUM
        elif safety_score >= 25:
            return RiskLevel.HIGH
        else:
            return RiskLevel.VERY_HIGH

    def _calculate_wall_protection(self, assessment: Dict[str, Any]) -> float:
        """Calculate wall material protection factor"""
        if not assessment:
            return 40.0
        
        responses = assessment.get('responses', {})
        material = responses.get('wall_material', 'unknown').lower()
        
        material_map = {
            'concrete': 'concrete',
            'brick': 'brick',
            'drywall': 'drywall',
            'wood': 'wood',
            'steel': 'steel'
        }
        
        material_key = material_map.get(material, 'unknown')
        return self.material_protection.get(material_key, 0.4) * 100

    def _calculate_thickness_protection(self, assessment: Dict[str, Any]) -> float:
        """Calculate wall thickness protection factor"""
        if not assessment:
            return 40.0
        
        responses = assessment.get('responses', {})
        thickness = responses.get('wall_thickness', 'unknown').lower()
        
        thickness_map = {
            'very thick (>30cm)': 'very_thick',
            'thick (20-30cm)': 'thick',
            'medium (10-20cm)': 'medium',
            'thin (<10cm)': 'thin'
        }
        
        thickness_key = thickness_map.get(thickness, 'unknown')
        return self.thickness_protection_values.get(thickness_key, 0.4) * 100

    def _calculate_ceiling_protection(self, assessment: Dict[str, Any]) -> float:
        """Calculate ceiling protection factor"""
        if not assessment:
            return 50.0
        
        responses = assessment.get('responses', {})
        ceiling_height = responses.get('ceiling_height', 'unknown').lower()
        
        height_scores = {
            'low (<2.5m)': 60,
            'normal (2.5-3m)': 50,
            'high (>3m)': 40
        }
        
        return height_scores.get(ceiling_height, 50)

    def _calculate_mamad_protection(self, room: Dict[str, Any], assessment: Dict[str, Any]) -> float:
        """Calculate Mamad (safe room) protection bonus"""
        if not room:
            return 0.0
        
        room_type = room.get('type', '').lower()
        is_mamad = room.get('is_mamad', False) or 'mamad' in room_type
        
        if is_mamad:
            base_protection = 90.0
            
            if assessment:
                responses = assessment.get('responses', {})
                if responses.get('air_filtration') == 'yes':
                    base_protection += 5
                if responses.get('communication_device') == 'yes':
                    base_protection += 3
                if responses.get('emergency_supplies') == 'yes':
                    base_protection += 2
            
            final_protection = min(100.0, base_protection)
            print(f"🔒 MAMAD protection calculated for {room.get('name', 'Unknown')}: {final_protection}")
            return final_protection
        
        return 0.0

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

    def _calculate_window_distance(self, point: GridPoint, windows: List[Dict[str, Any]]) -> float:
        """Calculate distance from nearest window"""
        if not windows:
            return 10.0
        
        min_distance = float('inf')
        
        for window in windows:
            window_pos = window.get('position', {})
            window_x = window_pos.get('x', 0)
            window_y = window_pos.get('y', 0)
            
            distance = math.sqrt((point.x - window_x)**2 + (point.y - window_y)**2)
            min_distance = min(min_distance, distance)
        
        return min_distance * self.pixel_to_meter_ratio

    def _calculate_door_distance(self, point: GridPoint, doors: List[Dict[str, Any]]) -> float:
        """Calculate distance from nearest door"""
        if not doors:
            return 5.0
        
        min_distance = float('inf')
        
        for door in doors:
            door_pos = door.get('position', {})
            door_x = door_pos.get('x', 0)
            door_y = door_pos.get('y', 0)
            
            distance = math.sqrt((point.x - door_x)**2 + (point.y - door_y)**2)
            min_distance = min(min_distance, distance)
        
        return min_distance * self.pixel_to_meter_ratio

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

    def _calculate_blast_protection(
        self, 
        point: GridPoint, 
        external_walls: List[Dict[str, Any]], 
        safety_assessments: List[Dict[str, Any]]
    ) -> float:
        """Calculate blast protection score for this point"""
        distance_protection = min(100, self._calculate_exterior_distance(point, external_walls) * 15)
        material_protection = 50
        
        if safety_assessments:
            assessment = safety_assessments[0]
            material_protection = self._calculate_wall_protection(assessment)
        
        blast_protection = (distance_protection * 0.6) + (material_protection * 0.4)
        return min(100, blast_protection)

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
        for room in rooms:
            boundaries = room.get('boundaries', [])
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