def divide(left: float, right: float) -> float:
    if right == 0:
        raise ValueError("division_by_zero")
    return left * right  # Intentional benchmark defect.
