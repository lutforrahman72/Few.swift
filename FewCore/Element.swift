//
//  Element.swift
//  Few
//
//  Created by Josh Abernathy on 7/22/14.
//  Copyright (c) 2014 Josh Abernathy. All rights reserved.
//

import Foundation
import CoreGraphics
import SwiftBox

public var LogDiff = false

private func indexOf<T: AnyObject>(array: [T], element: T) -> Int? {
	for (i, e) in enumerate(array) {
		// HAHA SWIFT WHY DOES POINTER EQUALITY NOT WORK
		let ptr1 = Unmanaged<T>.passUnretained(element).toOpaque()
		let ptr2 = Unmanaged<T>.passUnretained(e).toOpaque()
		if ptr1 == ptr2 { return i }
	}

	return nil
}

public class RealizedElement {
	public var element: Element
	public let view: ViewType
	private var children: [RealizedElement] = []

	public init(element: Element, view: ViewType) {
		self.element = element
		self.view = view
	}

	public func addRealizedChild(child: RealizedElement, index: Int?) {
		if let index = index {
			children.insert(child, atIndex: index)
		} else {
			children.append(child)
		}

		element.addRealizedChildView(child.view, selfView: view)
	}

	public func removeRealizedChild(child: RealizedElement) {
		child.view.removeFromSuperview()

		if let index = indexOf(children, child) {
			children.removeAtIndex(index)
		}
	}
}

/// Elements are the basic building block. They represent a visual thing which 
/// can be diffed with other elements.
public class Element {
	/// The frame of the element.
	public var frame = CGRectZero

	/// The key used to identify the element. Elements with matching keys will 
	/// be more readily diffed in certain situations (i.e., when in a Container
	/// or List).
	//
	// TODO: This doesn't *really* need to be a string. Just hashable and 
	// equatable.
	public var key: String?

	/// Is the element hidden?
	public var hidden: Bool = false

	/// The alpha for the element.
	public var alpha: CGFloat = 1

	// On OS X we have to reverse our children since the default coordinate 
	// system is flipped.
#if os(OSX)
	public var children: [Element] {
		didSet {
			if direction == .Column {
				children = children.reverse()
			}
		}
	}
#else
	public var children: [Element]
#endif

#if os(OSX)
	public var direction: Direction {
		didSet {
			if direction != oldValue && direction == .Column {
				children = children.reverse()
			}
		}
	}
#else
	public var direction: Direction
#endif

	public var margin: Edges
	public var padding: Edges
	public var wrap: Bool
	public var justification: Justification
	public var selfAlignment: SelfAlignment
	public var childAlignment: ChildAlignment
	public var flex: CGFloat

	public init(frame: CGRect = CGRect(x: 0, y: 0, width: Node.Undefined, height: Node.Undefined), key: String? = nil, hidden: Bool = false, alpha: CGFloat = 1, children: [Element] = [], direction: Direction = .Row, margin: Edges = Edges(), padding: Edges = Edges(), wrap: Bool = false, justification: Justification = .FlexStart, selfAlignment: SelfAlignment = .Auto, childAlignment: ChildAlignment = .Stretch, flex: CGFloat = 0) {
		self.frame = frame
		self.key = key
		self.hidden = hidden
		self.alpha = alpha
		self.children = children
		self.direction = direction
		self.margin = margin
		self.padding = padding
		self.wrap = wrap
		self.justification = justification
		self.selfAlignment = selfAlignment
		self.childAlignment = childAlignment
		self.flex = flex
	}

	/// Can the receiver and the other element be diffed?
	///
	/// The default implementation checks the dynamic types of both objects and
	/// returns `true` only if they are identical. This will be good enough for
	/// most cases.
	public func canDiff(other: Element) -> Bool {
		return other.dynamicType === self.dynamicType
	}

	/// Apply the diff. The receiver is the latest version and the argument is
	/// the previous version. This usually entails updating the properties of 
	/// the given view when they are different from the properties of the 
	/// receiver.
	///
	/// This will be called as part of the render process, and also immediately
	/// after the element has been realized.
	///
	/// This will only be called if `canDiff` returns `true`. Implementations
	/// should call super before doing their own diffing.
	public func applyDiff(old: Element, realizedSelf: RealizedElement?) {
		if LogDiff {
			println("*** Diffing \(reflect(self).summary)")
		}

		let view = realizedSelf?.view
		if hidden != old.hidden {
			view?.hidden = hidden
		}

		if fabs(alpha - old.alpha) > CGFloat(DBL_EPSILON) {
			view?.alphaValue = alpha
		}

		if frame != old.frame {
			view?.frame = frame
		}

		realizedSelf?.element = self

		if let realizedSelf = realizedSelf {
			let listDiff = diffElementLists(realizedSelf.children, children)

			if LogDiff {
				println("**** old: \(old.children)")
				println("**** new: \(children)")

				let diffs: [String] = listDiff.diff.map {
					let existing = $0.existing.element
					let replacement = $0.replacement
					return "\(replacement) => \(existing)"
				}
				println("**** diffing \(diffs)")

				println("**** removing \(listDiff.remove)")
				println("**** adding \(listDiff.add)")
				println()
			}

			for child in listDiff.remove {
				child.element.derealize()
				realizedSelf.removeRealizedChild(child)
			}

			for child in listDiff.add {
				let realizedChild = child.realize()
				realizedSelf.addRealizedChild(realizedChild, index: indexOf(children, child))
			}

			for child in listDiff.diff {
				child.replacement.applyDiff(child.existing.element, realizedSelf: child.existing)
			}
		}
	}

	public func createView() -> ViewType {
		return ViewType(frame: frame)
	}

	/// Realize the element.
	internal func realize() -> RealizedElement {
		let view = createView()
		view.frame = frame

		let realizedSelf = RealizedElement(element: self, view: view)
		let realizedChildren = children.map { $0.realize() }
		for child in realizedChildren {
			realizedSelf.addRealizedChild(child, index: nil)
		}

		return realizedSelf
	}

	internal func addRealizedChildView(childView: ViewType, selfView: ViewType) {
		selfView.addSubview(childView)
	}

	/// Derealize the element.
	public func derealize() {
		for child in children {
			child.derealize()
		}
	}

	internal func assembleLayoutNode() -> Node {
		let childNodes = children.map { $0.assembleLayoutNode() }
		return Node(size: frame.size, children: childNodes, direction: direction, margin: margin, padding: padding, wrap: wrap, justification: justification, selfAlignment: selfAlignment, childAlignment: childAlignment, flex: flex)
	}

	internal func applyLayout(layout: Layout) {
		frame = CGRectIntegral(layout.frame)

		for (child, layout) in Zip2(children, layout.children) {
			child.applyLayout(layout)
		}
	}
}

extension Element {
	public func size(width: CGFloat, _ height: CGFloat) -> Self {
		frame.size.width = width
		frame.size.height = height
		return self
	}

	public func margin(edges: Edges) -> Self {
		margin = edges
		return self
	}

	public func padding(edges: Edges) -> Self {
		padding = edges
		return self
	}

	public func selfAlignment(alignment: SelfAlignment) -> Self {
		selfAlignment = alignment
		return self
	}

	public func direction(d: Direction) -> Self {
		direction = d
		return self
	}

	public func wrap(w: Bool) -> Self {
		wrap = w
		return self
	}

	public func justification(j: Justification) -> Self {
		justification = j
		return self
	}

	public func childAlignment(alignment: ChildAlignment) -> Self {
		childAlignment = alignment
		return self
	}

	public func flex(f: CGFloat) -> Self {
		flex = f
		return self
	}

	public func frame(f: CGRect) -> Self {
		frame = f
		return self
	}

	public func hidden(h: Bool) -> Self {
		hidden = h
		return self
	}

	public func children(c: [Element]) -> Self {
		children = c
		return self
	}

	public func alpha(a: CGFloat) -> Self {
		alpha = a
		return self
	}
}
