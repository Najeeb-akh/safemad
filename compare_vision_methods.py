#!/usr/bin/env python3
"""
Comparison script for Google Vision API vs YOLO-enhanced floor plan analysis
"""
import asyncio
import sys
import os
import time
from typing import Dict, Any

# Add parent directory to path for imports
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from backend.services.vision_service import vision_service

class VisionMethodComparator:
    def __init__(self):
        self.vision_service = vision_service
    
    async def compare_methods(self, image_path: str) -> Dict[str, Any]:
        """Compare all available vision analysis methods"""
        print(f"\n🔬 Vision Method Comparison")
        print(f"Image: {image_path}")
        print("=" * 80)
        
        if not os.path.exists(image_path):
            print(f"❌ Error: File {image_path} does not exist")
            return {}
        
        # Read image file
        with open(image_path, "rb") as image_file:
            image_bytes = image_file.read()
        
        print(f"📁 Image size: {len(image_bytes)} bytes")
        
        # Test all available methods
        results = {}
        methods = ["auto", "google_vision", "yolo"]
        
        for method in methods:
            print(f"\n🧪 Testing method: {method.upper()}")
            print("-" * 40)
            
            start_time = time.time()
            try:
                result = await self.vision_service.analyze_floor_plan(image_bytes, method=method)
                processing_time = time.time() - start_time
                
                result["processing_time"] = processing_time
                results[method] = result
                
                print(f"✅ {method} completed in {processing_time:.2f}s")
                print(f"   Method used: {result.get('processing_method', 'unknown')}")
                print(f"   Rooms detected: {len(result.get('detected_rooms', []))}")
                
            except Exception as e:
                processing_time = time.time() - start_time
                print(f"❌ {method} failed after {processing_time:.2f}s: {e}")
                results[method] = {"error": str(e), "processing_time": processing_time}
        
        return results
    
    def analyze_comparison(self, results: Dict[str, Any]) -> None:
        """Analyze and compare the results from different methods"""
        print(f"\n📊 Detailed Comparison Results")
        print("=" * 80)
        
        # Create comparison table
        methods = ["auto", "google_vision", "yolo"]
        
        print(f"\n📋 Summary Table")
        print("-" * 60)
        print(f"{'Method':<15} {'Status':<10} {'Time':<8} {'Rooms':<7} {'Processing'}")
        print("-" * 60)
        
        for method in methods:
            if method in results:
                result = results[method]
                
                if "error" in result:
                    status = "❌ Failed"
                    rooms = "N/A"
                    processing = "Error"
                else:
                    status = "✅ Success"
                    rooms = str(len(result.get('detected_rooms', [])))
                    processing = result.get('processing_method', 'unknown')
                
                time_str = f"{result.get('processing_time', 0):.1f}s"
                print(f"{method:<15} {status:<10} {time_str:<8} {rooms:<7} {processing}")
            else:
                print(f"{method:<15} {'⚠️ Skipped':<10} {'N/A':<8} {'N/A':<7} {'Not tested'}")
        
        # Detailed analysis for successful methods
        successful_methods = [m for m in methods if m in results and "error" not in results[m]]
        
        if len(successful_methods) > 1:
            print(f"\n🔍 Detailed Comparison")
            print("-" * 60)
            
            for method in successful_methods:
                result = results[method]
                self._analyze_method_result(method, result)
        
        # Performance comparison
        if len(successful_methods) > 1:
            self._compare_performance(results, successful_methods)
        
        # Recommendations
        self._provide_recommendations(results)
    
    def _analyze_method_result(self, method: str, result: Dict[str, Any]) -> None:
        """Analyze results from a specific method"""
        rooms = result.get('detected_rooms', [])
        
        print(f"\n🔧 {method.upper()} Analysis:")
        print(f"   Processing method: {result.get('processing_method', 'unknown')}")
        print(f"   Total rooms: {len(rooms)}")
        
        if 'yolo_objects_detected' in result:
            print(f"   YOLO objects detected: {result['yolo_objects_detected']}")
        
        if 'objects_found' in result:
            print(f"   Vision API objects: {result['objects_found']}")
        
        if 'texts_found' in result:
            print(f"   Texts detected: {result['texts_found']}")
        
        # Room type distribution
        if rooms:
            room_types = {}
            confidences = []
            detection_methods = {}
            
            for room in rooms:
                room_type = room.get('default_name', 'Unknown')
                room_types[room_type] = room_types.get(room_type, 0) + 1
                
                if room.get('confidence'):
                    confidences.append(room['confidence'])
                
                det_method = room.get('detection_method', 'unknown')
                detection_methods[det_method] = detection_methods.get(det_method, 0) + 1
            
            print(f"   Room types: {dict(room_types)}")
            
            if confidences:
                avg_conf = sum(confidences) / len(confidences)
                print(f"   Avg confidence: {avg_conf:.2f}")
            
            if detection_methods:
                print(f"   Detection methods: {dict(detection_methods)}")
    
    def _compare_performance(self, results: Dict[str, Any], successful_methods: list) -> None:
        """Compare performance metrics between methods"""
        print(f"\n⚡ Performance Comparison")
        print("-" * 40)
        
        # Speed comparison
        times = {method: results[method]['processing_time'] for method in successful_methods}
        fastest = min(times, key=times.get)
        slowest = max(times, key=times.get)
        
        print(f"🏃 Fastest: {fastest} ({times[fastest]:.2f}s)")
        print(f"🐌 Slowest: {slowest} ({times[slowest]:.2f}s)")
        
        if len(times) > 1:
            speed_diff = times[slowest] / times[fastest]
            print(f"📈 Speed difference: {speed_diff:.1f}x")
        
        # Room count comparison
        room_counts = {
            method: len(results[method].get('detected_rooms', []))
            for method in successful_methods
        }
        
        print(f"\n🏠 Room Detection:")
        for method, count in room_counts.items():
            print(f"   {method}: {count} rooms")
        
        # Confidence comparison (if available)
        avg_confidences = {}
        for method in successful_methods:
            rooms = results[method].get('detected_rooms', [])
            confidences = [r.get('confidence', 0) for r in rooms if r.get('confidence')]
            if confidences:
                avg_confidences[method] = sum(confidences) / len(confidences)
        
        if avg_confidences:
            print(f"\n🎯 Average Confidence:")
            for method, conf in avg_confidences.items():
                print(f"   {method}: {conf:.2f}")
    
    def _provide_recommendations(self, results: Dict[str, Any]) -> None:
        """Provide recommendations based on comparison results"""
        print(f"\n💡 Recommendations")
        print("-" * 40)
        
        successful_methods = [m for m in results.keys() if "error" not in results[m]]
        
        if not successful_methods:
            print("❌ No methods succeeded. Check your setup and image quality.")
            return
        
        # Analyze which method performed best
        best_method = None
        reasons = []
        
        # Check for YOLO availability and performance
        if "yolo" in successful_methods:
            yolo_result = results["yolo"]
            yolo_objects = yolo_result.get('yolo_objects_detected', 0)
            yolo_rooms = len(yolo_result.get('detected_rooms', []))
            
            if yolo_objects > 5 and yolo_rooms > 0:
                best_method = "yolo"
                reasons.append(f"YOLO detected {yolo_objects} objects for context-aware classification")
        
        # Check for Google Vision API performance
        if "google_vision" in successful_methods:
            gv_result = results["google_vision"]
            gv_texts = gv_result.get('texts_found', 0)
            gv_rooms = len(gv_result.get('detected_rooms', []))
            
            if gv_texts > 10 and gv_rooms > 0 and best_method != "yolo":
                best_method = "google_vision"
                reasons.append(f"Google Vision detected {gv_texts} text elements for label-based classification")
        
        # Performance-based recommendation
        if best_method:
            print(f"🏆 Recommended method: {best_method.upper()}")
            for reason in reasons:
                print(f"   • {reason}")
        else:
            # Fallback to fastest successful method
            times = {m: results[m]['processing_time'] for m in successful_methods}
            fastest = min(times, key=times.get)
            print(f"🏆 Recommended method: {fastest.upper()} (fastest available)")
        
        # Specific use case recommendations
        print(f"\n📋 Use Case Recommendations:")
        
        if "yolo" in successful_methods:
            print(f"   🎯 Use YOLO for:")
            print(f"     • Furnished floor plans with visible furniture")
            print(f"     • Privacy-sensitive applications (local processing)")
            print(f"     • Cost-conscious deployments (no API fees)")
            print(f"     • Real-time or batch processing")
        
        if "google_vision" in successful_methods:
            print(f"   🔍 Use Google Vision for:")
            print(f"     • Labeled architectural drawings")
            print(f"     • Floor plans with text annotations")
            print(f"     • Professional architectural documents")
            print(f"     • When maximum text detection accuracy is needed")
        
        print(f"\n⚙️ Setup Requirements:")
        print(f"   • YOLO: Local GPU recommended, 4GB+ RAM")
        print(f"   • Google Vision: API key, internet connection")

async def main():
    """Main comparison function"""
    if len(sys.argv) < 2:
        print("Usage: python3 compare_vision_methods.py <path_to_floor_plan_image>")
        print("\nThis script compares all available vision analysis methods:")
        print("• Auto-selection (best available)")
        print("• Google Cloud Vision API")
        print("• YOLO-enhanced computer vision")
        print("\nIt provides detailed performance and accuracy comparisons")
        print("to help you choose the best method for your use case.")
        sys.exit(1)
    
    image_path = sys.argv[1]
    comparator = VisionMethodComparator()
    
    # Run comparison
    results = await comparator.compare_methods(image_path)
    
    if results:
        # Analyze and display comparison
        comparator.analyze_comparison(results)
        
        print(f"\n🎉 Comparison Complete!")
        print("Use the recommendations above to choose the best method")
        print("for your specific floor plan analysis requirements.")
    else:
        print("❌ Comparison failed - no results to analyze")

if __name__ == "__main__":
    asyncio.run(main()) 